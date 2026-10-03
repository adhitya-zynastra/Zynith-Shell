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
    color: Theme.surface

    property string route: Quickshell.env("ZYNITH_SETTINGS_ROUTE") || "home"
    property string query: ""

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
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.surface
    }

    // ── sidebar ─────────────────────────────────────────────────────────────
    Rectangle {
        id: sidebar
        width: 236
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        color: Theme.surfaceLow

        Column {
            anchors.fill: parent
            anchors.margins: Metrics.s5
            spacing: Metrics.s2

            Label {
                role: "headline"
                text: "Settings"
                bottomPadding: Metrics.s3
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
                    name: "adjustments-horizontal"
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
                        text: "Search"
                    }
                }
            }

            Item {
                width: 1
                height: Metrics.s2
            }

            Repeater {
                model: Routes.search(win.query)

                delegate: Column {
                    required property var modelData
                    required property int index
                    width: parent.width

                    readonly property var all: Routes.search(win.query)
                    readonly property bool groupStart: modelData.group !== "" && (index === 0 || all[index - 1].group !== modelData.group)

                    Label {
                        visible: parent.groupStart
                        role: "caption"
                        tone: "faint"
                        caps: true
                        topPadding: Metrics.s4
                        bottomPadding: Metrics.s2
                        leftPadding: Metrics.s3
                        text: parent.modelData.group
                    }
                    ListRow {
                        width: parent.width
                        height: 38
                        icon: parent.modelData.icon
                        title: parent.modelData.title
                        active: win.route === parent.modelData.id
                        onClicked: win.route = parent.modelData.id
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

            sourceComponent: ({
                    home: homePage,
                    experience: experiencePage,
                    appearance: appearancePage,
                    animation: animationPage,
                    wallpaper: wallpaperPage,
                    lock: lockPage,
                    bars: barsPage,
                    control: controlPage,
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

            onLoaded: fadeIn.restart()
            NumberAnimation {
                id: fadeIn
                target: page
                property: "opacity"
                from: 0
                to: 1
                duration: Motion.contentIn
                easing.type: Motion.standardEasing
            }
        }
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
