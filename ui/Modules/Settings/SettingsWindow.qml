import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Components
import qs.Services

FloatingWindow {
    id: win

    title: "Zynith Settings"
    implicitWidth: 980
    implicitHeight: 660
    // Settings is read, so it takes the material with restraint: Solid opaque; Glass and Blur a little denser than
    // the panels (never under 0.78). Behind it niri puts the wallpaper (Glass, xray) or the blurred desktop (Blur).
    readonly property real sheetAlpha: Material.solid ? 1 : Math.max(0.78, Material.fillAlpha + 0.12)
    color: "transparent"

    property string route: Quickshell.env("ZYNITH_SETTINGS_ROUTE") || "home"
    property string query: ""
    // a setting found by search: its page shows it alone until the filter is cleared
    property string focusTitle: ""
    onRouteChanged: {
        if (!settingJump)
            focusTitle = "";
        fadeIn.restart();
    }
    property bool settingJump: false
    function goToSetting(hit: var): void {
        settingJump = true;
        focusTitle = hit.title;
        route = hit.route.id;
        settingJump = false;
    }
    // Ryoku's rail: plain categories; the technical pages wait behind "Advanced settings" (search still finds
    // them, and the open page always stays listed, so switching Advanced off never strands you)
    readonly property bool advanced: Config.settingsAdvanced
    readonly property var routeMatches: query.trim() !== "" ? Routes.search(query) : Routes.routes.filter(r => advanced || !r.advanced || r.id === route)
    readonly property var settingMatches: query.trim().length >= 2 ? SettingsIndex.search(query) : []
    Component.onCompleted: SettingsIndex.load()

    onClosed: Qt.quit()

    IpcHandler {
        target: "settings"
        function open(route: string): void {
            win.route = Routes.find(route).id;
        }
        // the whole current page, as an image of this window's own content only (for documentation)
        function capture(path: string): void {
            page.grabToImage(r => r.saveToFile(path));
        }
        // what the search box would find (for testing): routes and settings, as JSON
        function search(text: string): string {
            win.query = text;
            return JSON.stringify({ routes: win.routeMatches.map(r => r.id), settings: win.settingMatches.map(h => h.title + " → " + h.route.id) });
        }
        function goTo(text: string, n: int): void {
            const hits = SettingsIndex.search(text);
            if (hits.length > n)
                win.goToSetting(hits[n]);
        }
        function captureSidebar(path: string): void {
            sidebar.grabToImage(r => r.saveToFile(path));
        }
    }

    Rectangle {
        id: backdrop
        anchors.fill: parent
        color: Theme.alpha(Theme.surface, win.sheetAlpha)
    }
    BlurRegion {
        window: win
        item: backdrop
    }

    // ── sidebar ─────────────────────────────────────────────────────────────
    Rectangle {
        id: sidebar
        width: 236
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        color: Theme.alpha(Theme.surfaceLow, win.sheetAlpha)

        Flickable {
            anchors.fill: parent
            anchors.margins: Metrics.s5
            contentHeight: sideColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
        Column {
            id: sideColumn
            width: parent.width
            spacing: Metrics.s2

            // the masthead: the name over its section mark, in a hairline box
            Rectangle {
                width: parent.width
                height: 52
                color: "transparent"
                border.width: Metrics.hairline
                border.color: Theme.hairline
                radius: Metrics.radiusControl
                Column {
                    anchors.left: parent.left
                    anchors.leftMargin: Metrics.s4
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1
                    Label {
                        role: "title"
                        font.letterSpacing: 2
                        text: "ZYNITH"
                    }
                    Label {
                        role: "data"
                        tone: "faint"
                        text: "//SETTINGS_"
                    }
                }
            }
            Item {
                width: 1
                height: Metrics.s2
            }

            Rectangle {
                width: parent.width
                height: 34
                radius: Metrics.radiusMd
                color: Theme.hover

                Icon {
                    id: searchIcon
                    anchors.left: parent.left
                    anchors.leftMargin: Metrics.s3
                    anchors.verticalCenter: parent.verticalCenter
                    name: "search"
                    tone: "faint"
                    size: 14
                }
                TextInput {
                    anchors.left: searchIcon.right
                    anchors.leftMargin: Metrics.s2
                    anchors.right: parent.right
                    anchors.rightMargin: Metrics.s3
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.ink
                    font.family: Type.ui
                    font.pixelSize: Type.body
                    selectionColor: Theme.accentSoft
                    onTextChanged: win.query = text

                    Label {
                        visible: parent.text === ""
                        role: "body"
                        tone: "faint"
                        text: "Search settings…"
                    }
                }
            }

            Item {
                width: 1
                height: Metrics.s2
            }

            // with a query: the pages that match, then the settings themselves (each to its page)
            Label {
                visible: win.settingMatches.length > 0
                role: "data"
                tone: "faint"
                topPadding: Metrics.s4
                bottomPadding: Metrics.s2
                leftPadding: Metrics.s3
                text: "Settings · " + win.settingMatches.length
            }
            Repeater {
                model: win.settingMatches
                delegate: Item {
                    id: hit
                    required property var modelData
                    width: parent.width
                    height: hitText.implicitHeight + Metrics.s2 * 2
                    Rectangle {
                        anchors.fill: parent
                        radius: Metrics.radiusMd
                        color: hitArea.containsMouse ? Theme.hover : "transparent"
                    }
                    Column {
                        id: hitText
                        x: Metrics.s3
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - Metrics.s3 * 2
                        spacing: 1
                        Label {
                            width: parent.width
                            role: "label"
                            elide: Text.ElideRight
                            text: hit.modelData.title
                        }
                        Label {
                            width: parent.width
                            role: "micro"
                            tone: "faint"
                            elide: Text.ElideRight
                            text: hit.modelData.route.title + "  ›  " + hit.modelData.group
                        }
                    }
                    MouseArea {
                        id: hitArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: win.goToSetting(hit.modelData)
                    }
                }
            }

            Repeater {
                model: win.routeMatches

                delegate: Column {
                    id: navItem
                    required property var modelData
                    required property int index
                    width: parent.width

                    readonly property var all: win.routeMatches
                    readonly property bool groupStart: modelData.group !== "" && (index === 0 || all[index - 1].group !== modelData.group)
                    readonly property bool current: win.route === modelData.id

                    // "03  DESKTOP ───": the group's number and name in tracked mono over a hairline
                    Item {
                        visible: navItem.groupStart
                        width: parent.width
                        height: visible ? 34 : 0
                        Label {
                            id: groupLabel
                            anchors.left: parent.left
                            anchors.leftMargin: Metrics.s2
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: Metrics.s2
                            role: "data"
                            tone: navItem.all.some(r => r.group === navItem.modelData.group && r.id === win.route) ? "muted" : "faint"
                            text: Routes.groupIndex(navItem.modelData.group) + "  " + navItem.modelData.group.toUpperCase()
                        }
                        Rectangle {
                            anchors.left: groupLabel.right
                            anchors.leftMargin: Metrics.s3
                            anchors.right: parent.right
                            anchors.verticalCenter: groupLabel.verticalCenter
                            height: Metrics.hairline
                            color: Theme.hairline
                        }
                    }
                    // selection is inversion: the live page is an ink plate with a "//" lead
                    Rectangle {
                        width: parent.width
                        height: 34
                        radius: Metrics.radiusControl
                        color: navItem.current ? Theme.ink : navArea.containsMouse ? Theme.hover : "transparent"
                        Label {
                            anchors.left: parent.left
                            anchors.leftMargin: Metrics.s3
                            anchors.right: parent.right
                            anchors.rightMargin: Metrics.s3
                            anchors.verticalCenter: parent.verticalCenter
                            role: "body"
                            elide: Text.ElideRight
                            color: navItem.current ? Theme.surface : Theme.ink
                            text: (navItem.current ? "//  " : "") + navItem.modelData.title
                        }
                        MouseArea {
                            id: navArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: win.route = navItem.modelData.id
                        }
                    }
                }
            }

            // the rail foot: the Advanced gate
            Item {
                width: parent.width
                height: Metrics.s5
            }
            Rectangle {
                width: parent.width
                height: Metrics.hairline
                color: Theme.hairline
            }
            Item {
                width: parent.width
                height: 44
                Label {
                    anchors.left: parent.left
                    anchors.leftMargin: Metrics.s2
                    anchors.verticalCenter: parent.verticalCenter
                    role: "body"
                    text: "Advanced settings"
                }
                Toggle {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    checked: win.advanced
                    onToggled: Config.setSettingsAdvanced(!win.advanced)
                }
            }
        }
        }
    }

    // ── page ────────────────────────────────────────────────────────────────
    Flickable {
        anchors.left: sidebar.right
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        contentHeight: page.implicitHeight + Metrics.s7 * 2
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Loader {
            id: page
            x: Metrics.s7
            y: Metrics.s7
            width: parent.width - Metrics.s7 * 2
            opacity: 0
            readonly property var routeSpec: Routes.find(win.route)
            sourceComponent: routeSpec.section ? nativePage : routePage
        }
    }

    // a native section's own page
    Component {
        id: nativePage
        NativePage {
            route: page.routeSpec
            focusTitle: win.focusTitle
        }
    }
    // a Zynith page, and under it the native settings on the same subject
    Component {
        id: routePage
        Column {
            spacing: Metrics.s7
            // the page's eyebrow, as Ryoku's page head: its group, numbered
            Label {
                visible: win.focusTitle === "" && page.routeSpec.group !== ""
                role: "data"
                tone: "faint"
                bottomPadding: -Metrics.s5
                text: "—  " + Routes.groupIndex(page.routeSpec.group) + "  " + page.routeSpec.group.toUpperCase()
            }
            Loader {
                id: zynithPage
                width: parent.width
                active: win.focusTitle === ""
                visible: active
                sourceComponent: ({
                    home: homePage,
                    experience: experiencePage,
                    appearance: appearancePage,
                    animation: animationPage,
                    wallpaper: wallpaperPage,
                    lock: lockPage,
                    bars: barsPage,
                    control: controlPage,
                    widgets: widgetsPage,
                    osd: osdPage,
                    shell: shellPage,
                    launcher: launcherPage,
                    notifications: notificationsPage,
                    media: mediaPage,
                    surfaces: surfacesPage,
                    window: windowPage,
                    network: networkPage,
                    bluetooth: bluetoothPage,
                    plugins: pluginsPage,
                    about: aboutPage
                    })[win.route] ?? homePage
                onLoaded: {
                    // a page may send you to another (the native settings page to Zynith's own)
                    if (item.navigate !== undefined)
                        item.navigate.connect(r => win.route = Routes.find(r).id);
                }
            }
            // a setting reached by search: say which, and a way back to the whole page
            Row {
                visible: win.focusTitle !== ""
                spacing: Metrics.s3
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    role: "headline"
                    text: page.routeSpec.title
                }
                Chip {
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "x"
                    text: "Showing “" + win.focusTitle + "” · whole page"
                    onClicked: win.focusTitle = ""
                }
            }
            Repeater {
                model: page.routeSpec.native ?? []
                delegate: NativeBlock {
                    required property var modelData
                    width: parent.width
                    entry: modelData
                    query: win.focusTitle
                    advanced: win.advanced || win.focusTitle !== ""
                }
            }
        }
    }
    Connections {
        target: page
        function onLoaded(): void {
            fadeIn.restart();
        }
    }
    NumberAnimation {
        id: fadeIn
        target: page
        property: "opacity"
        from: 0
        to: 1
        duration: Motion.contentIn
        easing.type: Motion.standardEasing
    }


    Component {
        id: homePage
        HomePage {
            onNavigate: id => win.route = id
        }
    }
    Component {
        id: experiencePage
        ExperiencePage {}
    }
    Component {
        id: appearancePage
        AppearancePage {}
    }
    Component {
        id: barsPage
        BarsPage {}
    }
    Component {
        id: windowPage
        WindowPage {}
    }
    Component {
        id: aboutPage
        AboutPage {}
    }
    Component {
        id: animationPage
        AnimationPage {}
    }
    Component {
        id: wallpaperPage
        WallpaperPage {}
    }
    Component {
        id: lockPage
        LockPage {}
    }
    Component {
        id: controlPage
        ControlPanelPage {}
    }
    Component {
        id: widgetsPage
        WidgetsPage {}
    }
    Component {
        id: osdPage
        OsdPage {}
    }
    Component {
        id: shellPage
        ShellSettingsPage {}
    }
    Component {
        id: launcherPage
        LauncherPage {}
    }
    Component {
        id: notificationsPage
        NotificationsPage {}
    }
    Component {
        id: mediaPage
        MediaPage {}
    }
    Component {
        id: surfacesPage
        SurfacesPage {}
    }
    Component {
        id: networkPage
        NetworkPage {}
    }
    Component {
        id: bluetoothPage
        BluetoothPage {}
    }
    Component {
        id: pluginsPage
        PluginsPage {}
    }
}
