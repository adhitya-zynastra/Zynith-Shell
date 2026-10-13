import QtQuick
import QtQuick.Effects
import Quickshell
import Zynith.Native
import qs.Common
import qs.Components
import qs.Services

// The wallpaper browser. Two sources — your images and Wallpaper Engine — each with its views (Images: all,
// favourites, recent, folders; Live: installed, favourites, recent, collection). Two layouts over the same
// state (wallpaper.toml layout):
//   carousel  a cinematic arc across the dimmed desktop, the focused wallpaper large in the middle and its
//             neighbours receding; one glass card above holds the controls
//   grid      a panel with a hero of the focused wallpaper over a grid of the library
// Every view is filtered from state the Wallpapers service already holds, so switching is immediate; the
// shell's change events keep it current. Moving the focus never applies — a click on the focused card or
// Enter does.
//
// Keys: arrows move · Enter applies · / searches · Tab next view · Shift+Tab other source
//       F favourite · C collection (live) · L layout · Esc leaves (or clears the search first)
Item {
    id: root

    property var screen: null
    property real visibleProgress: 1
    property bool active: true
    property string context: ""

    readonly property bool carousel: Config.wallpaper.layout !== "grid"
    readonly property bool bare: carousel
    readonly property Item blurItem: carousel ? (layoutLoader.item?.controlCard ?? null) : null
    readonly property int preferredWidth: Math.min(1120, Math.round((screen?.width ?? 1600) * 0.74))
    readonly property real preferredTop: 0.07
    implicitHeight: carousel ? (screen?.height ?? 1080) : (layoutLoader.item?.implicitHeight ?? 0)

    // ── browse state (kept in the service, so the browser reopens where it was left) ──
    readonly property bool live: Wallpapers.browse.source === "live"
    readonly property string view: live ? Wallpapers.browse.liveView : Wallpapers.browse.imageView
    property string query: ""
    signal focusSearch

    readonly property var views: live ? [
        { key: "installed", label: "Installed", icon: "layout-grid", count: Wallpapers.liveFor("installed", "", "az").length },
        { key: "favorites", label: "Favourites", icon: "heart", count: Wallpapers.liveFavorites.length },
        { key: "recent", label: "Recent", icon: "history", count: Wallpapers.liveRecent.length },
        { key: "collection", label: "Collection", icon: "stack-2", count: Wallpapers.liveCollection.length }
    ] : [
        { key: "all", label: "All", icon: "layout-grid", count: Wallpapers.images.length },
        { key: "favorites", label: "Favourites", icon: "heart", count: Wallpapers.favorites.length },
        { key: "recent", label: "Recent", icon: "history", count: -1 }
    ].concat(Wallpapers.folders.map(f => ({ key: "folder:" + f.name, label: f.name, icon: "folder", count: f.count })))

    // one shape for both sources: { key, title, subtitle, thumb, still, animated, favorite, collected, current }
    readonly property int thumbWidth: Math.min(ExperiencePolicy.thumbnailSize, 480)
    readonly property var entries: {
        const sort = Wallpapers.browse.sort;
        if (live) {
            const favs = Wallpapers.liveFavorites, coll = Wallpapers.liveCollection;
            const showing = Wallpapers.mode === "live" ? (Wallpapers.livePending || Wallpapers.liveCurrent) : "";
            return Wallpapers.liveFor(view, query, sort).map(i => ({
                        key: i.id,
                        title: i.title,
                        subtitle: i.kind,
                        thumb: i.preview !== "" ? Thumbnails.url(i.preview, root.thumbWidth) : "",
                        still: i.preview !== "" ? Thumbnails.url(i.preview, 1280) : "",
                        animated: i.preview.toLowerCase().endsWith(".gif") ? "file://" + i.preview : "",
                        source: i.preview,
                        favorite: favs.includes(i.id),
                        collected: coll.includes(i.id),
                        current: i.id === showing
                    }));
        }
        const favs = Wallpapers.favorites;
        const showing = Wallpapers.mode === "static" ? Wallpapers.current : "";
        return Wallpapers.imagesFor(view, query, sort).map(i => ({
                    key: i.path,
                    title: i.name,
                    subtitle: i.folder,
                    thumb: Thumbnails.url(i.path, root.thumbWidth),
                    still: Thumbnails.url(i.path, 1280),
                    animated: "",
                    source: i.path,
                    favorite: favs.includes(i.path),
                    collected: false,
                    current: i.path === showing
                }));
    }

    property int focusIndex: 0
    readonly property var focused: entries[Math.min(focusIndex, entries.length - 1)] ?? null
    onEntriesChanged: if (focusIndex >= entries.length)
        focusIndex = Math.max(0, entries.length - 1)
    // grid columns, so Up and Down move a row there; the carousel has one row
    property int rowLength: 1

    function setView(key: string): void {
        if (live)
            Wallpapers.browse = Object.assign({}, Wallpapers.browse, { liveView: key });
        else
            Wallpapers.browse = Object.assign({}, Wallpapers.browse, { imageView: key });
        focusIndex = 0;
    }
    function setSource(source: string): void {
        Wallpapers.browse = Object.assign({}, Wallpapers.browse, { source: source, touched: true });
        focusOnCurrent();
    }
    function cycleView(back: bool): void {
        const i = views.findIndex(v => v.key === view);
        setView(views[(i + (back ? views.length - 1 : 1)) % views.length].key);
    }
    function focusOnCurrent(): void {
        focusIndex = Math.max(0, entries.findIndex(e => e.current));
    }
    function move(delta: int): void {
        if (entries.length > 0)
            focusIndex = Math.max(0, Math.min(entries.length - 1, focusIndex + delta));
    }
    function activate(index: int): void {
        // the focused card applies; any other one is focused first
        if (index !== focusIndex)
            focusIndex = index;
        else
            apply(entries[index]);
    }
    // where the chosen card is on the screen: the new wallpaper grows from there (the centre for the carousel's
    // focused card, which sits mid-screen)
    readonly property var revealOrigin: ({
            x: (screen?.x ?? 0) + (screen?.width ?? 0) / 2,
            y: (screen?.y ?? 0) + (screen?.height ?? 0) / 2
        })
    function apply(entry: var): void {
        if (!entry)
            return;
        applied++;
        if (live)
            Wallpapers.applyLive(entry.key);
        else if ((Wallpapers.browse.output ?? "") !== "" && Quickshell.screens.length > 1)
            Wallpapers.applyImageOn(Wallpapers.browse.output, entry.key, revealOrigin);
        else
            Wallpapers.applyImage(entry.key, revealOrigin);
    }
    function toggleFavorite(entry: var): void {
        if (!entry)
            return;
        if (live)
            Wallpapers.toggleLiveFavorite(entry.key);
        else
            Wallpapers.toggleFavorite(entry.key);
    }
    function toggleLayout(): void {
        Config.write("wallpaper", "layout", carousel ? "grid" : "carousel");
    }
    function close(): void {
        PanelRouter.close(screen.name);
    }

    // what it was opened for (wallpaper live | images) arrives just after the panel itself
    onContextChanged: if (active && (context === "live" || context === "images"))
        setSource(context)
    onActiveChanged: active ? open() : Wallpapers.release()
    Component.onCompleted: if (active)
        open()
    Component.onDestruction: if (active)
        Wallpapers.release()
    function open(): void {
        Wallpapers.retain();
        query = "";
        if (context === "live" || context === "images")
            Wallpapers.browse = Object.assign({}, Wallpapers.browse, { source: context });
        else if (!Wallpapers.browse.touched)
            Wallpapers.browse = Object.assign({}, Wallpapers.browse, { source: Wallpapers.mode === "live" ? "live" : "images" });
        focusOnCurrent();
        keys.forceActiveFocus();
    }
    // the first answer after opening lands the focus on what is showing
    Connections {
        target: Wallpapers
        function onSyncedChanged(): void {
            if (root.active)
                root.focusOnCurrent();
        }
    }

    Item {
        id: keys
        focus: true
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                root.close();
            } else if (event.key === Qt.Key_Left) {
                root.move(-1);
            } else if (event.key === Qt.Key_Right) {
                root.move(1);
            } else if (event.key === Qt.Key_Up) {
                root.move(-root.rowLength);
            } else if (event.key === Qt.Key_Down) {
                root.move(root.rowLength);
            } else if (event.key === Qt.Key_PageUp) {
                root.move(-root.rowLength * 3);
            } else if (event.key === Qt.Key_PageDown) {
                root.move(root.rowLength * 3);
            } else if (event.key === Qt.Key_Home) {
                root.move(-root.entries.length);
            } else if (event.key === Qt.Key_End) {
                root.move(root.entries.length);
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.apply(root.focused);
            } else if (event.key === Qt.Key_Backtab) {
                root.setSource(root.live ? "images" : "live");
            } else if (event.key === Qt.Key_Tab) {
                root.cycleView(false);
            } else if (event.key === Qt.Key_Slash) {
                root.focusSearch();
            } else if (event.key === Qt.Key_F) {
                root.toggleFavorite(root.focused);
            } else if (event.key === Qt.Key_C && root.live && root.focused) {
                Wallpapers.toggleCollection(root.focused.key);
            } else if (event.key === Qt.Key_L) {
                root.toggleLayout();
            } else {
                return;
            }
            event.accepted = true;
        }
    }

    Loader {
        id: layoutLoader
        width: parent.width
        height: root.carousel ? parent.height : implicitHeight
        sourceComponent: root.carousel ? carouselLayout : gridLayout
    }

    // ════ shared pieces ════════════════════════════════════════════════════

    // source, search, sort and layout on one line
    Component {
        id: toolbar
        Item {
            height: 48

            Segmented {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 236
                current: root.live ? "live" : "images"
                options: [
                    { key: "images", label: "Images" },
                    { key: "live", label: "Wallpaper Engine" }
                ]
                onPicked: key => root.setSource(key)
            }

            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Metrics.s1

                SearchField {
                    id: field
                    anchors.verticalCenter: parent.verticalCenter
                    width: 220
                    placeholder: root.live ? "Search Workshop titles" : "Search images"
                    onTextChanged: {
                        if (root.query !== text) {
                            root.query = text;
                            root.focusIndex = 0;
                        }
                    }
                    onMoved: delta => root.move(delta * root.rowLength)
                    onTabbed: back => root.cycleView(back)
                    onAccepted: root.apply(root.focused)
                    onEscaped: keys.forceActiveFocus()
                    Connections {
                        target: root
                        function onQueryChanged(): void {
                            if (field.text !== root.query)
                                field.text = root.query;
                        }
                        function onFocusSearch(): void {
                            field.focusField();
                        }
                    }
                }
                IconButton {
                    id: sortButton
                    anchors.verticalCenter: parent.verticalCenter
                    readonly property var order: ["az", "za", "newest", "oldest"]
                    readonly property var glyphs: ({ az: "sort-ascending", za: "sort-descending", newest: "clock", oldest: "history" })
                    icon: glyphs[Wallpapers.browse.sort] ?? "sort-ascending"
                    tone: "muted"
                    enabled: root.view === "installed" || root.view === "all" || root.view.startsWith("folder:")
                    onClicked: {
                        const i = order.indexOf(Wallpapers.browse.sort);
                        Wallpapers.browse = Object.assign({}, Wallpapers.browse, { sort: order[(i + 1) % order.length] });
                    }
                }
                IconButton {
                    anchors.verticalCenter: parent.verticalCenter
                    icon: root.carousel ? "layout-grid" : "layout-collage"
                    tone: "muted"
                    onClicked: root.toggleLayout()
                }
            }
        }
    }

    // the views, as chips that scroll sideways when there are many folders
    Component {
        id: viewChips
        Flickable {
            height: 32
            contentWidth: viewRow.implicitWidth
            flickableDirection: Flickable.HorizontalFlick
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            // the views as tracked tabs with their counts; the current one's mark glides under it
            Item {
                id: viewRow
                implicitWidth: viewTabs.implicitWidth
                height: 32
                Row {
                    id: viewTabs
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Metrics.s6
                    Repeater {
                        model: root.views
                        delegate: Item {
                            id: viewTab
                            required property var modelData
                            readonly property bool current: root.view === modelData.key
                            implicitWidth: tabText.implicitWidth
                            implicitHeight: tabText.implicitHeight
                            Row {
                                id: tabText
                                spacing: Metrics.s2
                                Label {
                                    role: "data"
                                    tone: viewTab.current ? "ink" : viewArea.containsMouse ? "muted" : "faint"
                                    text: viewTab.modelData.label
                                }
                                Label {
                                    visible: (viewTab.modelData.count ?? -1) >= 0
                                    role: "data"
                                    tone: viewTab.current ? "accent" : "faint"
                                    text: viewTab.modelData.count ?? ""
                                }
                            }
                            MouseArea {
                                id: viewArea
                                anchors.fill: parent
                                anchors.margins: -6
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.setView(viewTab.modelData.key)
                            }
                        }
                    }
                }
                Rectangle {
                    readonly property Item under: viewTabs.children[Math.max(0, root.views.findIndex(v => v.key === root.view))] ?? null
                    x: under ? under.x : 0
                    width: under ? under.width : 0
                    y: viewTabs.y + viewTabs.height + 4
                    height: 1.5
                    radius: 1
                    color: Theme.accent
                    Glide on x {}
                    Glide on width {}
                }
            }
        }
    }

    // the source's own controls: the live carousel and stop; for images a count, random and rescan
    Component {
        id: sourceActions
        Item {
            height: 40

            Row {
                visible: root.live
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: Metrics.s3

                Toggle {
                    anchors.verticalCenter: parent.verticalCenter
                    checked: Wallpapers.carousel.enabled
                    onToggled: Wallpapers.setCarousel(!Wallpapers.carousel.enabled, Wallpapers.carousel.interval, Wallpapers.carousel.order)
                }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    role: "label"
                    text: "Rotate the collection"
                }
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    opacity: Wallpapers.carousel.enabled ? 1 : 0.45
                    Repeater {
                        // the presets, plus an interval set elsewhere (IPC accepts any from 10 s)
                        readonly property var presets: [{ s: 60, l: "1m" }, { s: 300, l: "5m" }, { s: 900, l: "15m" }, { s: 1800, l: "30m" }, { s: 3600, l: "1h" }]
                        readonly property int interval: Wallpapers.carousel.interval
                        model: presets.some(p => p.s === interval) ? presets : [{ s: interval, l: interval < 60 ? interval + "s" : interval % 60 === 0 ? (interval / 60) + "m" : interval + "s" }].concat(presets)
                        delegate: Chip {
                            required property var modelData
                            text: modelData.l
                            active: Wallpapers.carousel.interval === modelData.s
                            onClicked: Wallpapers.setCarousel(Wallpapers.carousel.enabled, modelData.s, Wallpapers.carousel.order)
                        }
                    }
                }
                IconButton {
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "arrows-shuffle"
                    active: Wallpapers.carousel.order === "shuffle"
                    tone: "muted"
                    onClicked: Wallpapers.setCarousel(Wallpapers.carousel.enabled, Wallpapers.carousel.interval, Wallpapers.carousel.order === "shuffle" ? "sequential" : "shuffle")
                }
                IconButton {
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "player-skip-forward-filled"
                    tone: "muted"
                    enabled: Wallpapers.liveCollection.length > 1
                    onClicked: Wallpapers.nextLive()
                }
            }

            Row {
                visible: !root.live
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: Metrics.s2

                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    role: "data"
                    tone: "faint"
                    text: Wallpapers.images.length + " images in " + Wallpapers.directory.replace(Paths.home, "~")
                }
                IconButton {
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "arrows-shuffle"
                    tone: "muted"
                    onClicked: Wallpapers.random()
                }
                IconButton {
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "refresh"
                    tone: "muted"
                    onClicked: Wallpapers.rescan()
                }
                // which screen an image goes to, once there is more than one
                Row {
                    visible: Quickshell.screens.length > 1
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Chip {
                        icon: "device-desktop"
                        text: "All screens"
                        active: (Wallpapers.browse.output ?? "") === ""
                        onClicked: Wallpapers.browse = Object.assign({}, Wallpapers.browse, { output: "" })
                    }
                    Repeater {
                        model: Quickshell.screens
                        delegate: Chip {
                            required property var modelData
                            text: modelData.name
                            active: Wallpapers.browse.output === modelData.name
                            onClicked: Wallpapers.browse = Object.assign({}, Wallpapers.browse, { output: modelData.name })
                        }
                    }
                }
            }

            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Metrics.s3

                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: text !== ""
                    role: "caption"
                    tone: Wallpapers.error !== "" ? "danger" : "faint"
                    text: Wallpapers.error !== "" ? Wallpapers.error : root.live && Wallpapers.unsupported > 0 && root.view === "installed" ? Wallpapers.unsupported + " can’t be rendered on Linux" : ""
                }
                Chip {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Wallpapers.mode === "live"
                    icon: "player-stop-filled"
                    text: "Stop live"
                    onClicked: Wallpapers.stopLive()
                }
            }
        }
    }

    // what to say when a view is empty
    readonly property string emptyText: Wallpapers.scanning || (live && Wallpapers.discovering) ? "Looking…" : live && Wallpapers.problem !== "" ? Wallpapers.problem : query !== "" ? "Nothing matches “" + query + "”" : view === "favorites" ? "Right-click or press F to make a favourite" : view === "collection" ? "Press C to add to the collection the carousel rotates through" : view === "recent" ? "Wallpapers you apply appear here" : "No wallpapers in " + Wallpapers.directory

    // ════ carousel ═════════════════════════════════════════════════════════
    // Choreography, all derived from the panel's linear progress (visibleProgress) so opening and closing
    // are the same motion run backwards: the control card drops in, the focused wallpaper rises first and its
    // neighbours follow outward on the spatial curve; closing takes the outer cards first. Focus moves glide on
    // a spring that can be retargeted mid-flight; a drag moves the arc with the pointer and a flick carries on.
    readonly property color tint: tone.ready ? tone.color : Theme.accent
    readonly property var backdropTint: carousel && tone.ready ? tone.color : undefined
    property real backdropDim: 1
    Tone {
        id: tone
        path: root.carousel ? (root.focused?.source ?? "") : ""
    }
    // applying: the backdrop lifts for a moment so the new wallpaper shows, and the card answers
    property int applied: 0
    SequentialAnimation {
        id: reveal
        Anim {
            target: root
            property: "backdropDim"
            to: 0.3
            role: "effects"
        }
        PauseAnimation {
            duration: Motion.reduced ? 0 : 900
        }
        Anim {
            target: root
            property: "backdropDim"
            to: 1
            role: "spatialSlow"
        }
    }
    // both layouts lift the backdrop; [wallpaper] close_on_apply closes once the change has had its moment
    onAppliedChanged: {
        if (!Motion.reduced)
            reveal.restart();
        if (Config.wallpaper.close_on_apply === true)
            closeAfter.restart();
    }
    Timer {
        id: closeAfter
        interval: Motion.reduced ? 0 : 650
        onTriggered: root.close()
    }

    Component {
        id: carouselLayout

        Item {
            id: stage
            readonly property alias controlCard: controls
            readonly property real vp: root.visibleProgress
            function phase(delay: real, span: real): real {
                return Motion.reduced ? (vp > 0 ? 1 : 0) : Math.max(0, Math.min(1, (vp - delay) / span));
            }

            // a tap on the dimmed desktop leaves; the wheel steps through the arc anywhere
            TapHandler {
                // only the desktop itself: a card, the caption or the controls keep the browser open
                onTapped: point => {
                    const x = point.position.x, y = point.position.y;
                    const onControls = x >= controls.x && x <= controls.x + controls.width && y >= controls.y && y <= controls.y + controls.height;
                    if (!onControls && band.childAt(x - band.x, y - band.y) === null)
                        root.close();
                }
            }
            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => band.scrollBy(event.angleDelta)
            }

            // ── the control card ──
            Glass {
                id: controls
                readonly property real p: Motion.bezier(Motion.enterCurve, stage.phase(0, 0.6))
                anchors.horizontalCenter: parent.horizontalCenter
                y: Math.round(parent.height * 0.06) - (1 - p) * 28
                width: Math.min(1000, parent.width - Metrics.s6 * 2)
                height: controlColumn.implicitHeight + Metrics.s4 * 2
                radius: Metrics.radiusSurface
                // unboxed: the controls float on the scene (the dimmed desktop); the wallpapers are the subject
                fill: "transparent"
                edge: false
                raised: false
                sheen: false
                opacity: p

                TapHandler {}
                Column {
                    id: controlColumn
                    x: Metrics.s5
                    y: Metrics.s4
                    width: parent.width - Metrics.s5 * 2
                    spacing: Metrics.s2

                    Loader {
                        width: parent.width
                        sourceComponent: toolbar
                    }
                    Loader {
                        width: parent.width
                        sourceComponent: viewChips
                    }
                    Rectangle {
                        width: parent.width
                        height: 1
                        color: Theme.rule
                    }
                    Loader {
                        width: parent.width
                        sourceComponent: sourceActions
                    }
                }
            }

            // ── the band ──
            Item {
                id: band
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: controls.bottom
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Metrics.s6

                // geometry after the native carousel (carousel_geometry.h): cards on an arc of 63°
                readonly property real arc: 3 * 0.3665
                readonly property real minScale: 0.52
                readonly property real falloff: 0.6
                readonly property real preferred: Config.wallpaper.card_width >= 320 ? Math.min(1400, Config.wallpaper.card_width) : 760
                readonly property real cardW: width <= 1920 ? Math.min(preferred, width * 0.40) : preferred
                readonly property real aspect: (root.screen?.height ?? 1080) / (root.screen?.width ?? 1920)
                readonly property real cardH: Math.round(cardW * aspect)
                readonly property real stride: cardW * 0.66
                readonly property var fit: fitArc(width, cardW, stride)
                readonly property real radius: stride / fit.step
                readonly property real centreY: height * 0.44

                function depthAt(theta: real): real {
                    const span = 1 - Math.cos(arc);
                    return Math.max(0, Math.min(1, (1 - Math.cos(theta)) / span));
                }
                function scaleAt(depth: real): real {
                    return 1 - (1 - minScale) * Math.pow(depth, falloff);
                }
                // as many cards a side as stay legible and show enough of themselves past their neighbour
                function fitArc(viewport: real, w: real, s: real): var {
                    let per = 0;
                    for (let n = 1; n <= 6; n++) {
                        const step = arc / (n + 1);
                        const r = s / step;
                        const centre = viewport / 2;
                        let nearer = centre + w / 2, fits = true;
                        for (let k = 1; k <= n && fits; k++) {
                            const th = k * step;
                            const sc = scaleAt(depthAt(th));
                            const half = w * sc / 2;
                            const x = centre + r * Math.sin(th);
                            const exposed = Math.min(x + half, viewport) - Math.max(x - half, nearer);
                            fits = sc >= 0.42 && exposed >= 0.2 * 2 * half;
                            nearer = Math.max(nearer, x + half);
                        }
                        if (!fits)
                            break;
                        per = n;
                    }
                    return { perSide: Math.max(1, per), step: arc / (Math.max(1, per) + 1) };
                }

                // where the arc is: the dragged position while a drag lasts, else a spring after the focus
                property real glided: root.focusIndex
                property bool glide: true
                // a spring where the profile has springs, a tween on the spatial curve otherwise; never a jump
                Glide on glided {
                    enabled: band.glide && !Motion.reduced
                    epsilon: 0.002
                }
                property real dragged: 0
                readonly property real pos: drag.active ? dragged : glided
                Connections {
                    target: root
                    function onFocusIndexChanged(): void {
                        if (drag.active)
                            return;
                        // a long jump (a new view, Home, End) lands at once
                        band.glide = Math.abs(root.focusIndex - band.glided) <= band.fit.perSide + 3;
                        band.glided = root.focusIndex;
                        band.glide = true;
                    }
                }

                // the pointer moves the arc 1:1; letting go carries the flick on and settles on a card
                DragHandler {
                    id: drag
                    target: null
                    xAxis.enabled: true
                    yAxis.enabled: false
                    property real from: 0
                    onActiveChanged: {
                        if (active) {
                            from = band.glided;
                            band.dragged = from;
                        } else {
                            const fling = -centroid.velocity.x / band.stride * 0.18;
                            const target = Math.max(0, Math.min(root.entries.length - 1, Math.round(band.dragged + fling)));
                            band.glide = false;
                            band.glided = band.dragged;
                            band.glide = true;
                            root.focusIndex = target;
                            band.glided = target;
                        }
                    }
                    onTranslationChanged: if (active) {
                        band.dragged = Math.max(-0.4, Math.min(root.entries.length - 0.6, from - translation.x / band.stride));
                        const nearest = Math.max(0, Math.min(root.entries.length - 1, Math.round(band.dragged)));
                        if (nearest !== root.focusIndex)
                            root.focusIndex = nearest;
                    }
                }

                property real wheelRest: 0
                function scrollBy(delta: point): void {
                    wheelRest += (delta.x !== 0 ? -delta.x : -delta.y);
                    while (Math.abs(wheelRest) >= 120) {
                        root.move(wheelRest > 0 ? 1 : -1);
                        wheelRest -= wheelRest > 0 ? 120 : -120;
                    }
                }

                // the opening: the deck rises (enter curve), then fans (spatial curve, with its small overshoot)
                readonly property real rise: Motion.bezier(Motion.enterCurve, stage.phase(0, 0.5))
                readonly property real spread: Motion.bezier(Motion.spatialCurve, stage.phase(0.22, 0.78))

                // only the neighbourhood exists: the arc and a few past each end, for the glide
                readonly property int lo: Math.max(0, root.focusIndex - fit.perSide - 3)
                readonly property var window: root.entries.slice(lo, root.focusIndex + fit.perSide + 4)

                Repeater {
                    model: ScriptModel {
                        values: band.window
                        objectProp: "key"
                    }

                    delegate: Item {
                        id: card
                        required property var modelData
                        required property int index
                        readonly property int entryIndex: band.lo + index
                        readonly property real offset: entryIndex - band.pos
                        // the deck: it rises as one, then fans out along the arc; closing folds it back first
                        readonly property real spread: band.spread
                        readonly property real theta: Math.max(-Math.PI / 2, Math.min(Math.PI / 2, offset * band.fit.step * spread))
                        readonly property real depth: band.depthAt(Math.abs(theta))
                        readonly property bool focused: entryIndex === root.focusIndex
                        readonly property bool shown: Math.abs(offset) <= band.fit.perSide + 1.2
                        readonly property real lift: hover.hovered && !focused ? 1 : 0

                        visible: shown && band.rise > 0.001
                        width: band.cardW
                        height: band.cardH
                        x: band.width / 2 + band.radius * Math.sin(theta) - width / 2
                        y: band.centreY - height / 2 + depth * band.cardH * 0.10 + (1 - band.rise) * band.cardH * 0.55 - liftY
                        z: 100 - Math.abs(offset) * 10
                        scale: band.scaleAt(depth) * (0.78 + 0.22 * band.rise) * pulse
                        // neighbours show as the deck opens; the focus with the rise
                        opacity: (focused ? Math.min(1, band.rise * 1.6) : Math.min(1, spread * 1.8) * Math.min(1, band.rise * 1.6)) * (1 - depth * 0.55 + lift * 0.15)

                        property real liftY: lift * 8
                        Behavior on liftY {
                            Anim {
                                role: "spatialFast"
                            }
                        }
                        // the applied card answers with a small swell
                        property real pulse: 1
                        SequentialAnimation {
                            id: swell
                            Anim {
                                target: card
                                property: "pulse"
                                to: 1.045
                                role: "effects"
                            }
                            Anim {
                                target: card
                                property: "pulse"
                                to: 1
                                role: "spatialFast"
                            }
                        }
                        Connections {
                            target: root
                            function onAppliedChanged(): void {
                                if (card.focused && !Motion.reduced)
                                    swell.restart();
                            }
                        }

                        // the glow under the focused card takes the wallpaper's own colour, and breathes
                        RectangularShadow {
                            anchors.fill: art
                            visible: ExperiencePolicy.shadows && Math.abs(card.offset) < 2.5
                            radius: Metrics.radiusLg
                            blur: card.focused ? 56 : 28
                            spread: card.focused ? 2 : 0
                            offset.y: card.focused ? 16 : 10
                            color: card.focused ? Theme.alpha(root.tint, 0.42 * breath) : Theme.alpha(Theme.shadow, 0.5 * (1 - card.depth))
                            property real breath: 1
                            SequentialAnimation on breath {
                                running: card.focused && ExperiencePolicy.richEffects && root.active && !Motion.reduced
                                loops: Animation.Infinite
                                NumberAnimation {
                                    to: 0.6
                                    duration: Motion.ms(2200)
                                    easing.type: Easing.InOutSine
                                }
                                NumberAnimation {
                                    to: 1
                                    duration: Motion.ms(2200)
                                    easing.type: Easing.InOutSine
                                }
                            }
                            Behavior on blur {
                                Anim {
                                    role: "spatialFast"
                                }
                            }
                        }

                        // the picture, a little larger than the card, slides against the arc's motion: parallax
                        Item {
                            id: art
                            anchors.fill: parent
                            layer.enabled: true
                            layer.smooth: true
                            layer.effect: MultiEffect {
                                maskEnabled: true
                                maskSource: cardMask
                                maskThresholdMin: 0.5
                                maskSpreadAtMin: 1
                            }

                            Rectangle {
                                anchors.fill: parent
                                color: Theme.well
                            }
                            Item {
                                id: plate
                                width: parent.width * 1.14
                                height: parent.height * 1.14
                                x: (parent.width - width) / 2 - Math.max(-1.5, Math.min(1.5, card.offset)) * parent.width * 0.045
                                y: (parent.height - height) / 2

                                Image {
                                    id: low
                                    anchors.fill: parent
                                    source: card.modelData.thumb
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    opacity: status === Image.Ready ? 1 : 0
                                    Behavior on opacity {
                                        Anim {
                                            role: "effects"
                                        }
                                    }
                                }
                                // the focused card is promoted to a sharp image once it is decoded
                                Image {
                                    id: sharp
                                    anchors.fill: parent
                                    source: card.focused ? card.modelData.still : ""
                                    // decoded at the size it is shown, not the wallpaper's own (a 4K original is
                                    // ~33 MB in memory for a card a few hundred pixels wide)
                                    sourceSize: Qt.size(Math.ceil(width), Math.ceil(height))
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    opacity: card.focused && status === Image.Ready ? 1 : 0
                                    Behavior on opacity {
                                        Anim {
                                            role: "effects"
                                        }
                                    }
                                }
                                AnimatedImage {
                                    anchors.fill: parent
                                    source: card.focused && ExperiencePolicy.richEffects && root.active ? card.modelData.animated : ""
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    playing: status === AnimatedImage.Ready
                                    opacity: status === AnimatedImage.Ready ? 1 : 0
                                    Behavior on opacity {
                                        Anim {
                                            role: "effects"
                                        }
                                    }
                                }
                            }
                            // a sheen across the top that fades with depth
                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                height: parent.height * 0.35
                                opacity: (1 - card.depth) * 0.5
                                gradient: Gradient {
                                    GradientStop {
                                        position: 0
                                        color: Theme.alpha("#ffffff", 0.10)
                                    }
                                    GradientStop {
                                        position: 1
                                        color: "transparent"
                                    }
                                }
                            }
                        }
                        Rectangle {
                            id: cardMask
                            anchors.fill: parent
                            radius: Metrics.radiusLg
                            visible: false
                            layer.enabled: true
                        }
                        Icon {
                            anchors.centerIn: parent
                            visible: low.status === Image.Error || card.modelData.thumb === ""
                            name: "photo-off"
                            size: 28
                            tone: "faint"
                        }
                        // the focus ring draws itself in; the showing-now card keeps a quiet one
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: -5
                            radius: Metrics.radiusLg + 5
                            color: "transparent"
                            border.width: card.focused ? 2 : card.modelData.current ? 1 : 0
                            border.color: card.focused ? Theme.mix(Theme.accent, root.tint, 0.35) : Theme.accentLine
                            opacity: card.focused ? 1 : 0.8
                            Behavior on border.color {
                                ColorAnim {}
                            }
                        }
                        Row {
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: Metrics.s3
                            spacing: 4
                            Badge {
                                visible: card.modelData.collected && root.view !== "collection"
                                icon: "stack-2"
                            }
                            Badge {
                                visible: card.modelData.favorite
                                icon: "heart-filled"
                                accent: true
                            }
                        }
                        Rectangle {
                            visible: card.modelData.current
                            anchors.left: parent.left
                            anchors.bottom: parent.bottom
                            anchors.margins: Metrics.s3
                            width: nowText.implicitWidth + Metrics.s4
                            height: 20
                            radius: 10
                            color: Theme.alpha(Theme.base, 0.72)
                            Label {
                                id: nowText
                                anchors.centerIn: parent
                                role: "micro"
                                caps: true
                                tone: "accent"
                                text: root.live && Wallpapers.livePending === card.modelData.key ? "Starting" : "Showing"
                            }
                        }

                        HoverHandler {
                            id: hover
                            cursorShape: Qt.PointingHandCursor
                        }
                        TapHandler {
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onTapped: (point, button) => {
                                if (button === Qt.RightButton)
                                    root.toggleFavorite(card.modelData);
                                else
                                    root.activate(card.entryIndex);
                                keys.forceActiveFocus();
                            }
                        }
                    }
                }

                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: band.centreY - height / 2
                    visible: root.entries.length === 0
                    opacity: stage.phase(0.2, 0.5)
                    role: "title"
                    tone: "muted"
                    text: root.emptyText
                }

                // ── what the focused card is, and what can be done with it ──
                Column {
                    id: info
                    readonly property real p: Motion.bezier(Motion.enterCurve, stage.phase(0.32, 0.6))
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: band.centreY + band.cardH / 2 + Metrics.s6 + (1 - p) * 18
                    width: Math.min(band.cardW * 1.5, parent.width - Metrics.s6 * 2)
                    spacing: Metrics.s3
                    visible: root.focused !== null
                    opacity: p

                    // the title slides in from the side the arc moved towards
                    Item {
                        width: parent.width
                        height: titleCol.implicitHeight
                        clip: false
                        property real shift: 0
                        property real fade: 1
                        Connections {
                            target: root
                            function onFocusIndexChanged(): void {
                                if (Motion.reduced)
                                    return;
                                const dir = root.focusIndex > titleCol.last ? 1 : -1;
                                titleCol.last = root.focusIndex;
                                slideIn.stop();
                                titleCol.parent.shift = dir * 18;
                                titleCol.parent.fade = 0.25;
                                slideIn.start();
                            }
                        }
                        ParallelAnimation {
                            id: slideIn
                            Anim {
                                target: titleCol.parent
                                property: "shift"
                                to: 0
                                role: "spatialFast"
                            }
                            Anim {
                                target: titleCol.parent
                                property: "fade"
                                to: 1
                                role: "effects"
                            }
                        }

                        Column {
                            id: titleCol
                            property int last: root.focusIndex
                            x: parent.shift
                            width: parent.width
                            opacity: parent.fade
                            spacing: 3
                            Label {
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                role: "headline"
                                font.family: Type.display
                                font.weight: Font.Light
                                text: root.focused?.title ?? ""
                            }
                            // where it is from, and where it stands in the set, as a readout
                            Label {
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                role: "data"
                                tone: "faint"
                                text: {
                                    const f = root.focused;
                                    if (!f)
                                        return "";
                                    const where = root.live ? "Wallpaper Engine · " + f.subtitle : f.subtitle;
                                    const n = String(root.entries.length).length;
                                    return [where, String(root.focusIndex + 1).padStart(n, "0") + " / " + root.entries.length].filter(s => s !== "").join("  ·  ");
                                }
                            }
                        }
                    }
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: Metrics.s2

                        RoundButton {
                            icon: root.focused?.favorite ? "heart-filled" : "heart"
                            on: root.focused?.favorite ?? false
                            onClicked: root.toggleFavorite(root.focused)
                        }
                        RoundButton {
                            visible: root.live
                            icon: root.focused?.collected ? "check" : "plus"
                            on: root.focused?.collected ?? false
                            onClicked: Wallpapers.toggleCollection(root.focused.key)
                        }
                        ApplyButton {
                            showing: root.focused?.current ?? false
                            onClicked: root.apply(root.focused)
                        }
                    }
                    // the keys, quietly
                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        role: "micro"
                        tone: "faint"
                        text: "←  →  browse     Enter  apply     F  favourite" + (root.live ? "     C  collection" : "") + "     Tab  view     /  search     L  grid"
                    }
                }
            }
        }
    }

    // ════ grid ═════════════════════════════════════════════════════════════
    Component {
        id: gridLayout

        Column {
            spacing: 0
            Component.onCompleted: root.rowLength = Qt.binding(() => grid.columns)
            Component.onDestruction: root.rowLength = 1

            // the focused wallpaper, large, cross-faded
            Item {
                id: hero
                width: parent.width
                height: Math.round(width * 0.30)
                clip: true

                Item {
                    id: heroImages
                    anchors.fill: parent
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        maskEnabled: true
                        maskSource: heroMask
                        maskThresholdMin: 0.5
                        maskSpreadAtMin: 1
                    }

                    property string source: root.focused?.still ?? ""
                    property bool flip: false
                    onSourceChanged: {
                        if (flip)
                            a.source = source;
                        else
                            b.source = source;
                        flip = !flip;
                    }
                    Image {
                        id: a
                        anchors.fill: parent
                        sourceSize: Qt.size(Math.ceil(width), Math.ceil(height))
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        opacity: !heroImages.flip && status === Image.Ready ? 1 : 0
                        Behavior on opacity {
                            NumberAnimation {
                                duration: Motion.contentIn
                                easing.type: Motion.standardEasing
                            }
                        }
                    }
                    Image {
                        id: b
                        anchors.fill: parent
                        sourceSize: Qt.size(Math.ceil(width), Math.ceil(height))
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        opacity: heroImages.flip && status === Image.Ready ? 1 : 0
                        Behavior on opacity {
                            NumberAnimation {
                                duration: Motion.contentIn
                                easing.type: Motion.standardEasing
                            }
                        }
                    }
                    AnimatedImage {
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        source: ExperiencePolicy.richEffects && root.active ? (root.focused?.animated ?? "") : ""
                        playing: status === AnimatedImage.Ready
                        opacity: status === AnimatedImage.Ready ? 1 : 0
                    }
                    Rectangle {
                        anchors.fill: parent
                        gradient: Gradient {
                            GradientStop {
                                position: 0.35
                                color: "transparent"
                            }
                            GradientStop {
                                position: 1
                                color: Theme.alpha(Theme.base, 0.86)
                            }
                        }
                    }
                }
                Rectangle {
                    id: heroMask
                    anchors.fill: parent
                    visible: false
                    layer.enabled: true
                    radius: Metrics.radiusLg
                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: parent.radius
                    }
                }

                Item {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: Metrics.s5
                    height: 52

                    Column {
                        anchors.left: parent.left
                        anchors.right: heroActions.left
                        anchors.rightMargin: Metrics.s4
                        anchors.bottom: parent.bottom
                        spacing: 2
                        Label {
                            width: parent.width
                            role: "headline"
                            font.weight: Font.Light
                            text: root.focused?.title ?? (Wallpapers.scanning || Wallpapers.discovering ? "" : "Nothing here yet")
                        }
                        Label {
                            width: parent.width
                            role: "caption"
                            tone: "muted"
                            text: {
                                const f = root.focused;
                                if (!f)
                                    return "";
                                const where = root.live ? "Wallpaper Engine · " + f.subtitle : f.subtitle;
                                return [where, f.current ? "showing now" : ""].filter(s => s !== "").join("  ·  ");
                            }
                        }
                    }
                    Row {
                        id: heroActions
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        spacing: Metrics.s2
                        visible: root.focused !== null

                        RoundButton {
                            icon: root.focused?.favorite ? "heart-filled" : "heart"
                            on: root.focused?.favorite ?? false
                            onClicked: root.toggleFavorite(root.focused)
                        }
                        RoundButton {
                            visible: root.live
                            icon: root.focused?.collected ? "check" : "plus"
                            on: root.focused?.collected ?? false
                            onClicked: Wallpapers.toggleCollection(root.focused.key)
                        }
                        ApplyButton {
                            showing: root.focused?.current ?? false
                            onClicked: root.apply(root.focused)
                        }
                    }
                }
            }

            Loader {
                x: Metrics.s4
                width: parent.width - Metrics.s4 * 2
                sourceComponent: toolbar
            }
            Loader {
                x: Metrics.s4
                width: parent.width - Metrics.s4 * 2
                sourceComponent: viewChips
            }
            Item {
                width: parent.width
                height: Metrics.s3
            }

            GridView {
                id: grid
                x: Metrics.s4
                width: parent.width - Metrics.s4 * 2
                readonly property int columns: Math.max(3, Math.floor(width / 196))
                cellWidth: Math.floor(width / columns)
                cellHeight: Math.round(cellWidth * 0.62) + 26
                height: cellHeight * 3
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                cacheBuffer: cellHeight * 2
                currentIndex: root.focusIndex
                highlightFollowsCurrentItem: false
                onCurrentIndexChanged: positionViewAtIndex(currentIndex, GridView.Contain)

                model: ScriptModel {
                    values: root.entries
                    objectProp: "key"
                }

                delegate: Item {
                    id: cell
                    required property var modelData
                    required property int index
                    readonly property bool focused: index === root.focusIndex
                    // the applied one answers with a small swell, then wears a check while it shows
                    property real pulse: 1
                    SequentialAnimation {
                        id: cellSwell
                        Anim {
                            target: cell
                            property: "pulse"
                            to: 1.06
                            role: "spatialFast"
                        }
                        Anim {
                            target: cell
                            property: "pulse"
                            to: 1
                            role: "spatialSlow"
                        }
                    }
                    Connections {
                        target: root
                        function onAppliedChanged(): void {
                            if (cell.focused && !Motion.reduced)
                                cellSwell.restart();
                        }
                    }

                    width: grid.cellWidth
                    height: grid.cellHeight

                    Item {
                        id: frame
                        x: 4
                        y: 4
                        width: parent.width - 8
                        height: Math.round(width * 0.62)
                        scale: (cell.focused ? 1.0 : hover.containsMouse ? 0.985 : 0.965) * cell.pulse

                        Glide on scale {
                            epsilon: 0.001
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: Metrics.radiusMd
                            color: Theme.well
                        }
                        Image {
                            id: thumb
                            anchors.fill: parent
                            source: cell.modelData.thumb
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            visible: false
                        }
                        MultiEffect {
                            anchors.fill: parent
                            source: thumb
                            maskEnabled: true
                            maskSource: cellMask
                            maskThresholdMin: 0.5
                            maskSpreadAtMin: 1
                            opacity: thumb.status === Image.Ready ? 1 : 0
                            Behavior on opacity {
                                NumberAnimation {
                                    duration: Motion.contentIn
                                }
                            }
                        }
                        Rectangle {
                            id: cellMask
                            anchors.fill: parent
                            radius: Metrics.radiusMd
                            visible: false
                            layer.enabled: true
                        }
                        Icon {
                            anchors.centerIn: parent
                            visible: thumb.status === Image.Error || cell.modelData.thumb === ""
                            name: "photo-off"
                            size: 20
                            tone: "faint"
                        }
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: -3
                            radius: Metrics.radiusMd + 3
                            color: "transparent"
                            border.width: cell.focused ? 2 : cell.modelData.current ? 1 : 0
                            border.color: cell.focused ? Theme.accent : Theme.accentLine
                        }
                        // what shows now: a check that scales in when it becomes so
                        Rectangle {
                            anchors.left: parent.left
                            anchors.bottom: parent.bottom
                            anchors.margins: Metrics.s2
                            width: 20
                            height: 20
                            radius: 10
                            color: Theme.accent
                            border.width: 2
                            border.color: Theme.alpha(Theme.base, 0.7)
                            scale: cell.modelData.current ? 1 : 0
                            visible: scale > 0.01
                            Glide on scale {
                                epsilon: 0.001
                            }
                            Icon {
                                anchors.centerIn: parent
                                name: "check"
                                size: 12
                                color: Theme.onAccent
                            }
                        }
                        Row {
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: Metrics.s2
                            spacing: 3
                            Badge {
                                visible: cell.modelData.collected && root.view !== "collection"
                                icon: "stack-2"
                            }
                            Badge {
                                visible: cell.modelData.favorite
                                icon: "heart-filled"
                                accent: true
                            }
                        }
                        MouseArea {
                            id: hover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: mouse => {
                                if (mouse.button === Qt.RightButton)
                                    root.toggleFavorite(cell.modelData);
                                else {
                                    root.focusIndex = cell.index;
                                    root.apply(cell.modelData);
                                }
                                keys.forceActiveFocus();
                            }
                        }
                    }
                    Label {
                        anchors.top: frame.bottom
                        anchors.topMargin: 5
                        x: frame.x + 2
                        width: frame.width - 4
                        role: "caption"
                        tone: cell.focused || cell.modelData.current ? "ink" : "muted"
                        text: cell.modelData.title
                    }
                }

                Label {
                    anchors.centerIn: parent
                    visible: grid.count === 0
                    role: "label"
                    tone: "faint"
                    text: root.emptyText
                }
            }

            Rectangle {
                width: parent.width - Metrics.s4 * 2
                x: Metrics.s4
                height: 1
                color: Theme.hairline
            }
            Loader {
                x: Metrics.s4
                width: parent.width - Metrics.s4 * 2
                height: 52
                sourceComponent: sourceActions
            }
        }
    }

    // ════ small parts ══════════════════════════════════════════════════════
    component RoundButton: Rectangle {
        id: rb
        property string icon
        property bool on: false
        signal clicked
        width: 38
        height: 38
        radius: 19
        color: rbArea.containsMouse ? Theme.alpha(Theme.base, 0.85) : Theme.alpha(Theme.base, 0.62)
        border.width: Metrics.hairline
        border.color: rb.on ? Theme.accentLine : Theme.hairline
        Icon {
            anchors.centerIn: parent
            name: rb.icon
            size: 16
            tone: rb.on ? "accent" : "ink"
        }
        MouseArea {
            id: rbArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: rb.clicked()
        }
    }

    // Apply, or a quiet "Showing" once it is the wallpaper
    component ApplyButton: Rectangle {
        id: ab
        property bool showing: false
        signal clicked
        width: abRow.implicitWidth + Metrics.s5 * 2
        height: 38
        radius: 19
        color: showing ? Theme.alpha(Theme.base, 0.62) : Theme.accent
        border.width: showing ? Metrics.hairline : 0
        border.color: Theme.accentLine
        opacity: abArea.pressed ? 0.85 : 1
        Row {
            id: abRow
            anchors.centerIn: parent
            spacing: Metrics.s2
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                name: ab.showing ? "check" : "corner-down-left"
                size: 15
                color: ab.showing ? Theme.accent : Theme.onAccent
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                role: "label"
                font.weight: Font.Medium
                color: ab.showing ? Theme.accent : Theme.onAccent
                text: ab.showing ? "Showing" : "Apply"
            }
        }
        MouseArea {
            id: abArea
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: ab.clicked()
        }
    }

    component Badge: Rectangle {
        property string icon
        property bool accent: false
        width: 22
        height: 22
        radius: 11
        color: Theme.alpha(Theme.base, 0.72)
        Icon {
            anchors.centerIn: parent
            name: parent.icon
            size: 12
            tone: parent.accent ? "accent" : "muted"
        }
    }
}
