import QtQuick
import qs.Common
import qs.Components
import qs.Services

// Picks the panel by id and cross-fades when navigating within one surface. New panels register here.
Item {
    id: root

    property string panelId: ""
    property var screen: null
    property real visibleProgress: 1
    property var history: []
    property bool active: true
    // what the panel was opened for, e.g. a launcher mode
    property string context: ""
    property int showings: 0
    // opened by resting the pointer on a bar icon: a quick look, without the hero
    property bool peek: false
    // a Control Panel page opened by itself (from its own bar icon): no hero, no tabs, its own size
    property bool focused: false
    // the card's top corners [left, right] (a full-bleed hero follows them)
    property var topCorners: [Metrics.radiusSurface, Metrics.radiusSurface]

    // the panel shown (the incoming one, from the moment it starts coming in)
    property string shownId: panelId

    // [control_panel] tab_bar / tabs: the Control Panel and its pages under one row of tabs (Caelestia's
    // dashboard); a tab switches the page in place
    readonly property var cfg: Config.controlPanel ?? ({})
    readonly property var tabNames: ({})   // names and icons: PanelCatalog
    readonly property var tabs: (cfg.tab_bar ?? true) ? Array.from(cfg.tabs ?? ["control", "media", "audio", "power", "weather", "calendar"]).map(t => String(t) === "home" ? "control" : String(t)).filter(t => panels[t] !== undefined).map(t => ({
                    id: t,
                    label: (cfg.tab_labels ?? {})[t] ?? (t === "control" ? "Dashboard" : PanelCatalog.label(t)),
                    icon: (cfg.tab_icons ?? {})[t] ?? PanelCatalog.icon(t)
                })) : []
    readonly property string tabId: shownId === "home" || shownId === "quick" ? "control" : shownId
    readonly property bool tabbed: !focused && tabs.length > 1 && tabs.some(t => t.id === tabId)

    // the hero over the Control Panel (and its tabs, with hero_pages = all)
    readonly property bool heroShown: !focused && (cfg.hero ?? true) && (!peek || (cfg.hero_on_peek ?? false)) && (tabId === "control" || (tabbed && (cfg.hero_pages ?? "all") === "all"))
    // With the hero over connected tabs the strip sits in the hero's bottom edge: the page's sheet starts just
    // under the picture and its tab rises through a groove cut in it (heroTabs)
    readonly property bool heroTabs: heroShown && connectedTabs
    readonly property real seam: Metrics.s2
    readonly property real tabRow: tabStrip.implicitHeight - tabStrip.sheetGap
    readonly property real contentTop: heroTabs ? hero.height + seam : (heroShown ? hero.height : 0) + (tabbed ? tabStrip.height : 0)
    implicitHeight: contentTop + (live.item?.implicitHeight ?? 0)
    // a panel may ask for its own width (0: the configured one)
    readonly property int preferredWidth: live.item?.preferredWidth ?? 0
    // where a centred panel's top sits, as a fraction of the screen height
    readonly property real preferredTop: live.item?.preferredTop ?? 0.22
    // a panel that covers the screen and draws its own surfaces; blurItem is the one the compositor blurs
    readonly property bool bare: live.item?.bare ?? false
    readonly property Item blurItem: live.item?.blurItem ?? null
    // a bare panel's say over the dimmed desktop: a colour to lean it towards, and how dim (0..1)
    readonly property var backdropTint: live.item?.backdropTint
    readonly property real backdropDim: live.item?.backdropDim ?? 1

    readonly property var panels: ({
            home: control,
            media: mediaPage,
            system: system,
            network: network,
            bluetooth: bluetooth,
            launcher: launcher,
            clipboard: clipboard,
            notifications: notifications,
            quick: control,
            wallpaper: wallpaper,
            control: control,
            session: session,
            island: island,
            audio: audioPage,
            power: powerPage,
            monitor: monitorPage,
            calendar: calendarPage,
            weather: weatherPage,
            "screen-time": screenTimePage
        })

    // Two slots: the panel shown and the one coming in. A change cross-fades them — the old one shrinks a
    // little and fades, the new one grows into place — while the card glides to its new size (Caelestia's
    // popouts). [panels] switch = none swaps at once; content_scale is how far they shrink (1 = not at all).
    readonly property string switchStyle: Config.panels?.switch ?? "morph"
    readonly property real contentScale: Math.max(0.5, Math.min(1, Config.panels?.content_scale ?? 0.94))
    property int front: 0
    readonly property Item live: front === 0 ? slotA : slotB
    readonly property Item livePage: live.item
    onLivePageChanged: if (screen) {
        const m = Object.assign({}, PanelRouter.livePages);
        m[screen.name] = livePage;
        PanelRouter.livePages = m;
    }
    readonly property Item leaving: front === 0 ? slotB : slotA
    property string idA: ""
    property string idB: ""
    onIdAChanged: put(slotA, idA)
    onIdBChanged: put(slotB, idB)

    // Pages are kept while this surface is: a switch back to one shows it as it was instead of building it in the
    // switch's first frame (25–77 ms for the heavy pages, measured). A kept page is inactive — no focus, no services
    // held — and the surface takes every page with it when it goes (on closing, or after its warm period). Bounded:
    // past keepPages the page used longest ago goes (six: the Control Panel's own tabs), and a page may decline to be
    // kept (trim). Measured: six kept pages, 1–11 MiB while the surface lives; nothing after.
    readonly property int keepPages: 6
    property var kept: ({})      // id -> page
    property var keptOrder: []   // ids, least recent first
    function pageFor(id: string, slot: Item): Item {
        let p = kept[id] ?? null;
        if (!p) {
            const c = panels[id] ?? null;
            if (!c)
                return null;
            // built where it shows, so it starts active (as a Loader's page did)
            p = c.createObject(slot, { width: root.width });
            built = true;
            wire(p);
            kept[id] = p;
        }
        keptOrder = keptOrder.filter(k => k !== id).concat([id]);
        return p;
    }
    // The oldest beyond the bound goes, and so does a page that says it is not worth keeping (keepable: false — one
    // that holds much while hidden, e.g. decoded pictures); never one on show. Only once nothing moves: a page torn
    // down mid-glide costs a frame there (destruction is deferred to the next turn of the event loop).
    function trim(): void {
        let excess = keptOrder.length - keepPages;
        for (const k of keptOrder.slice()) {
            const q = kept[k];
            if (q.parent === slotA || q.parent === slotB || (excess <= 0 && q.keepable !== false))
                continue;
            delete kept[k];
            keptOrder = keptOrder.filter(x => x !== k);
            excess--;
            q.destroy();
        }
    }
    // A page going out of sight keeps the keyboard focus it had, and keys would reach it unseen. The panel takes
    // it, so a key the new page leaves goes on to the surface's own keys.
    function letKeysGo(page: Item): void {
        let f = Window.activeFocusItem;
        while (f && f !== page)
            f = f.parent;
        if (f)
            root.forceActiveFocus();
    }
    // a slot shows a page: the one it held goes back to the kept pages
    function put(slot: Item, id: string): void {
        if (slot.item && slot.item !== kept[id]) {
            letKeysGo(slot.item);
            slot.item.parent = stash;
        }
        const p = id !== "" ? pageFor(id, slot) : null;
        if (slot.item === p)
            return;
        if (p) {
            const other = slot === slotA ? slotB : slotA;
            if (other.item === p)
                other.item = null;
            p.parent = slot;
        }
        slot.item = p;
    }
    Component.onCompleted: {
        if (idA === "" && idB === "")
            idA = panelId;
        // the catalog names only panels drawn here
        for (const e of PanelCatalog.entries)
            if (panels[e.id] === undefined)
                console.warn("zynith: PanelCatalog lists", e.id, "but PanelContent has no component for it");
    }

    onPanelIdChanged: {
        if ((front === 0 ? idA : idB) === panelId)
            return;
        const t0 = Date.now();
        built = false;
        change();
        // diagnostics: how long a switch held the frame before its first one could be drawn — the incoming page built,
        // or a kept one brought back (`ipc stats`)
        Diagnostics.record("switch-prep:" + (built ? "built" : "kept"), [Date.now() - t0]);
        Diagnostics.record("switch-prep:" + panelId, [Date.now() - t0]);
    }
    property bool built: false
    function change(): void {
        // the way the tabs travel, known before the page (and so the hero's heading) changes
        const from0 = tabIndexOf(front === 0 ? idA : idB), to0 = tabIndexOf(panelId);
        travel = tabbed && from0 >= 0 && to0 >= 0 && from0 !== to0 ? (to0 > from0 ? 1 : -1) : 0;
        shownId = panelId;
        // nothing shown yet, or not on screen: no cross-fade
        if (switchStyle === "none" || Motion.contentOut === 0 || (idA === "" && idB === "") || visibleProgress < 0.99) {
            swap.stop();
            if (front === 0) {
                idA = panelId;
                idB = "";
            } else {
                idB = panelId;
                idA = "";
            }
            live.opacity = 1;
            live.scale = 1;
            if (front === 0)
                idA = panelId;
            else
                idB = panelId;
            trim();
            return;
        }
        // between two tabs the pages move like one strip, in the direction the tab plate travels: the new page
        // comes in from that side while the old one leaves by the other (a shared axis with the plate above);
        // anything else cross-fades in place
        const from = tabIndexOf(front === 0 ? idA : idB);
        const to = tabIndexOf(panelId);
        const dir = tabbed && from >= 0 && to >= 0 && from !== to ? (to > from ? 1 : -1) : 0;
        // the incoming panel takes the free slot and becomes the live one at once (the card sizes to it)
        swap.stop();
        leaving.x = 0;
        if (front === 0)
            idB = panelId;
        else
            idA = panelId;
        front = 1 - front;
        letKeysGo(leaving.item);
        slideOut = -dir * slideDistance;
        // between tabs the pages are frames on one strip: both stay drawn, butted together, and move as one
        live.opacity = dir !== 0 ? 1 : 0;
        live.scale = dir !== 0 ? 1 : contentScale;
        live.x = dir * slideDistance;
        swap.start();
    }
    // how far a page travels on a tab change: enough to read as movement, never a full page (the card clips it)
    property int travel: 0
    // a whole page and the gap between frames: the old page leaves exactly as the new one arrives
    readonly property real slideDistance: Math.round(width + Metrics.s5)
    property real slideOut: 0
    function tabIndexOf(id: string): int {
        const t = id === "home" || id === "quick" ? "control" : id;
        return tabs.findIndex(x => x.id === t);
    }

    ParallelAnimation {
        id: swap
        NumberAnimation {
            target: root.leaving
            property: "opacity"
            to: root.slideOut !== 0 ? 1 : 0
            duration: Motion.contentOut + 40
            easing.type: Motion.exitEasing
        }
        NumberAnimation {
            target: root.leaving
            property: "scale"
            to: root.slideOut !== 0 ? 1 : root.contentScale
            duration: Motion.contentOut + 40
            easing.type: Motion.exitEasing
        }
        NumberAnimation {
            target: root.leaving
            property: "x"
            to: root.slideOut
            // on the strip both frames share one clock and one curve, so the seam between them never opens
            duration: root.slideOut !== 0 ? Motion.spatial : Motion.spatialFast
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root.slideOut !== 0 ? Motion.spatialCurve : Motion.spatialFastCurve
        }
        NumberAnimation {
            target: root.live
            property: "x"
            to: 0
            duration: Motion.spatial
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.spatialCurve
        }
        // a page changing in place comes in as the old one has mostly gone (two never read over each other);
        // on the strip it is already drawn and this is a no-op
        SequentialAnimation {
            PauseAnimation {
                duration: root.slideOut !== 0 ? Motion.contentOut * 0.8 : Motion.contentOut / 2
            }
            ParallelAnimation {
                NumberAnimation {
                    target: root.live
                    property: "opacity"
                    to: 1
                    duration: Motion.contentIn + 80
                    easing.type: Motion.enterEasing
                }
                NumberAnimation {
                    target: root.live
                    property: "scale"
                    to: 1
                    duration: Motion.spatial
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Motion.spatialCurve
                }
            }
        }
        onFinished: {
            // the old slot lets its panel go (back to the kept pages)
            if (root.front === 0)
                root.idB = "";
            else
                root.idA = "";
            root.leaving.opacity = 1;
            root.leaving.scale = 1;
            root.leaving.x = 0;
            root.trim();
        }
    }

    // a horizontal swipe over the panel (two fingers on a touchpad, or a tilt wheel) turns the page
    SwipeArea {
        anchors.fill: parent
        enabled: root.tabbed
        onStepped: by => root.stepTab(by)
    }

    // keyboard navigation over the tabs (PanelSurface's keys): true when it moved
    function stepTab(by: int): bool {
        if (!tabbed)
            return false;
        const i = tabs.findIndex(t => t.id === tabId);
        return goTab((i + by + tabs.length) % tabs.length);
    }
    function goTab(i: int): bool {
        if (!tabbed || i < 0 || i >= tabs.length)
            return false;
        PanelRouter.switchTo(tabs[i].id, screen.name);
        return true;
    }

    function wire(item: Item): void {
        item.width = Qt.binding(() => root.width);
        item.screen = Qt.binding(() => root.screen);
        item.visibleProgress = Qt.binding(() => root.visibleProgress);
        if (item.context !== undefined)
            item.context = Qt.binding(() => root.context);
        if (item.showings !== undefined)
            item.showings = Qt.binding(() => root.showings);
        // a kept page off show is inactive, as a closed panel's is
        if (item.active !== undefined)
            item.active = Qt.binding(() => root.active && item.parent !== stash);
        // `alone`, not `focused`: a panel may have a focused (card, row) of its own
        if (item.alone !== undefined)
            item.alone = Qt.binding(() => root.focused);
        // on the connected sheet a page draws no plates of its own (no box inside a box)
        if (item.onSheet !== undefined)
            item.onSheet = Qt.binding(() => root.connectedTabs);
        if (item.sheetInset !== undefined)
            item.sheetInset = Qt.binding(() => root.connectedTabs ? root.sheetInset : 0);
        // the strip carries the page's head when it has the room (see stripHead)
        if (item.headInStrip !== undefined)
            item.headInStrip = Qt.binding(() => root.headInStrip && !root.headInHero);
        if (item.headInHero !== undefined)
            item.headInHero = Qt.binding(() => root.headInHero);
        if (item.canGoBack !== undefined) {
            item.canGoBack = Qt.binding(() => root.history.length > 0);
            item.back.connect(() => PanelRouter.back(root.screen.name));
        }
    }

    Component {
        id: home
        HomePanel {}
    }
    Component {
        id: media
        MediaPanel {}
    }
    Component {
        id: system
        SystemPanel {}
    }
    Component {
        id: network
        NetworkPanel {}
    }
    Component {
        id: bluetooth
        BluetoothPanel {}
    }
    Component {
        id: launcher
        LauncherPanel {}
    }
    Component {
        id: clipboard
        ClipboardPanel {}
    }
    Component {
        id: notifications
        NotificationsPanel {}
    }
    Component {
        id: quick
        QuickSettingsPanel {}
    }
    Component {
        id: wallpaper
        WallpaperPanel {}
    }
    Component {
        id: session
        SessionPanel {}
    }
    Component {
        id: island
        IslandPanel {}
    }
    Component {
        id: control
        ControlPanel {}
    }
    // the native Control Center's tabs, as pages of their own
    Component {
        id: audioPage
        ModulePage {
            kind: "audio"
        }
    }
    Component {
        id: powerPage
        ModulePage {
            kind: "power"
        }
    }
    Component {
        id: monitorPage
        ModulePage {
            kind: "monitor"
        }
    }
    Component {
        id: calendarPage
        ModulePage {
            kind: "calendar"
        }
    }
    Component {
        id: weatherPage
        ModulePage {
            kind: "weather"
        }
    }
    Component {
        id: mediaPage
        ModulePage {
            kind: "media"
        }
    }
    Component {
        id: screenTimePage
        ModulePage {
            kind: "screen-time"
        }
    }

    PanelHero {
        id: hero
        visible: root.heroShown
        width: parent.width
        height: root.heroShown ? implicitHeight : 0
        active: root.active && root.heroShown
        // the page's heading (the dashboard: who you are), indexed as its tab
        heading: root.tabId === "control" || !root.headInHero ? null : Object.assign({ eyebrow: String(root.tabIndex + 1).padStart(2, "0") + " / " + (root.tabs[root.tabIndex]?.label ?? "") }, root.live.item?.heading ?? {})
        headingKey: root.tabId
        direction: root.travel
        topCorners: root.topCorners
        animate: root.visibleProgress >= 0.99
        bottomRoom: root.heroTabs ? root.tabRow - root.seam : 0
        notchLeft: root.heroTabs ? sheetShape.tabLeft - root.seam : 0
        notchRight: root.heroTabs ? sheetShape.tabRight + root.seam : 0
        notchTop: tabStrip.y - root.seam
    }
    // the hero carries the page's heading (the page then draws no header of its own)
    readonly property bool headInHero: heroShown && tabbed && tabId !== "control"
    // connected tabs: the page sits on one sheet, and the current tab is that same sheet reaching up into the
    // strip, so choosing a section moves the page's own surface rather than a separate highlight. The sheet is
    // the theme's well (a lift of whatever surface it sits on, contrast-aware), never a tone of its own: a fixed
    // tone read as a dark slab over a translucent panel on a light wallpaper.
    readonly property bool connectedTabs: tabbed && (cfg.tab_style ?? "connected") === "connected"
    // the sheet stands as far in from the card as the strip's content does, on every side it has: the panel's one
    // margin, so the sheet never runs into the card's edge while the strip beside it has room to spare
    readonly property real sheetInset: Metrics.s4
    // The strip's sides: the tabs sit centred, so the room left and right of them is the page's head (where it
    // is, what it shows, what can be done with it) and the sheet below holds only the page. With too little
    // room (many tabs, a narrow panel) the page keeps its own head.
    readonly property real sideRoom: Math.min(tabStrip.rowLeft, tabStrip.width - tabStrip.rowRight) - Metrics.s4
    readonly property bool headInStrip: connectedTabs && sideRoom >= tabStrip.iconSlot * 3
    readonly property int tabIndex: tabs.findIndex(t => t.id === tabId)
    // The sheet and the current tab's plate as one shape: drawn opaque inside one layer that takes the well's
    // opacity, so where they meet there is no doubled tone and no seam — one surface on any wallpaper.
    PageShape {
        id: sheetShape
        visible: root.connectedTabs
        anchors.fill: parent
        sheetX: root.sheetInset
        sheetY: root.contentTop
        sheetWidth: width - root.sheetInset * 2
        sheetHeight: Math.max(0, root.implicitHeight - root.contentTop - root.sheetInset)
        radius: Metrics.radiusPlate
        tabLeft: tabStrip.x + tabStrip.plateLeft
        tabRight: tabStrip.x + tabStrip.plateRight
        tabTop: tabStrip.y
        tabRadius: tabStrip.plateRadius
        fillet: tabStrip.plateRadius
        fill: Theme.well
        edge: Theme.alpha(Theme.ink, Material.solid ? 0.08 : 0.12)
    }
    // the page's head, in the strip's free side: its live caption (the date, the place, the player)
    Item {
        id: stripHead
        visible: root.headInStrip && !root.headInHero
        x: root.sheetInset
        y: tabStrip.y
        width: parent.width - root.sheetInset * 2
        height: tabStrip.height - tabStrip.sheetGap
        opacity: Math.max(0, Math.min(1, root.visibleProgress * 1.4 - 0.4))
        Label {
            anchors.left: parent.left
            anchors.leftMargin: Metrics.s2
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, tabStrip.x + tabStrip.rowLeft - stripHead.x - Metrics.s4 - Metrics.s2)
            visible: text !== ""
            role: "caption"
            tone: "muted"
            elide: Text.ElideRight
            text: root.live.item?.stripCaption ?? ""
        }
    }
    PanelTabs {
        id: tabStrip
        visible: root.tabbed
        x: Metrics.s5
        y: root.heroTabs ? root.contentTop - root.tabRow : (root.heroShown ? hero.height : 0) + Metrics.s3
        width: parent.width - Metrics.s5 * 2
        height: root.tabbed ? implicitHeight + (root.connectedTabs ? 0 : Metrics.s3) : 0
        tabs: root.tabs
        current: root.tabId
        showIcons: root.cfg.tab_icons_shown ?? true
        showLabels: root.cfg.tab_labels_shown ?? true
        style: root.cfg.tab_style ?? "connected"
        sheetColor: Theme.well
        drawPlate: false
        sheetLeft: root.sheetInset - x
        sheetRight: root.width - root.sheetInset - x
        sheetGap: Metrics.s2
        onPicked: id => PanelRouter.switchTo(id, root.screen.name)
    }

    Item {
        id: slotA
        property Item item: null
        y: root.contentTop
        width: parent.width
        transformOrigin: Item.Top
        visible: item !== null
    }
    Item {
        id: slotB
        property Item item: null
        y: root.contentTop
        width: parent.width
        transformOrigin: Item.Top
        visible: item !== null
    }
    // the kept pages not on show
    Item {
        id: stash
        visible: false
    }
}
