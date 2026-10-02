import QtQuick
import qs.Common
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

    // the panel actually shown; lags panelId by one fade when navigating
    property string shownId: panelId
    property real fade: 1

    implicitHeight: loader.item?.implicitHeight ?? 0
    // a panel may ask for its own width (0: the configured one)
    readonly property int preferredWidth: loader.item?.preferredWidth ?? 0
    // where a centred panel's top sits, as a fraction of the screen height
    readonly property real preferredTop: loader.item?.preferredTop ?? 0.22
    // a panel that covers the screen and draws its own surfaces; blurItem is the one the compositor blurs
    readonly property bool bare: loader.item?.bare ?? false
    readonly property Item blurItem: loader.item?.blurItem ?? null
    // a bare panel's say over the dimmed desktop: a colour to lean it towards, and how dim (0..1)
    readonly property var backdropTint: loader.item?.backdropTint
    readonly property real backdropDim: loader.item?.backdropDim ?? 1

    readonly property var panels: ({
            home: control,
            media: media,
            system: system,
            network: network,
            bluetooth: bluetooth,
            launcher: launcher,
            clipboard: clipboard,
            notifications: notifications,
            quick: control,
            wallpaper: wallpaper,
            control: control,
            session: session
        })

    onPanelIdChanged: {
        if (panelId === shownId)
            return;
        if (Motion.contentOut === 0) {
            shownId = panelId;
            return;
        }
        swap.restart();
    }

    SequentialAnimation {
        id: swap
        NumberAnimation {
            target: root
            property: "fade"
            to: 0
            duration: Motion.contentOut
            easing.type: Motion.exitEasing
        }
        ScriptAction {
            script: root.shownId = root.panelId
        }
        NumberAnimation {
            target: root
            property: "fade"
            to: 1
            duration: Motion.contentIn
            easing.type: Motion.standardEasing
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
        id: control
        ControlPanel {}
    }

    Loader {
        id: loader

        width: parent.width
        opacity: root.fade
        sourceComponent: root.panels[root.shownId] ?? null
        onLoaded: {
            item.screen = Qt.binding(() => root.screen);
            item.visibleProgress = Qt.binding(() => root.visibleProgress);
            if (item.context !== undefined)
                item.context = Qt.binding(() => root.context);
            if (item.showings !== undefined)
                item.showings = Qt.binding(() => root.showings);
            if (item.active !== undefined)
                item.active = Qt.binding(() => root.active);
            if (item.canGoBack !== undefined) {
                item.canGoBack = Qt.binding(() => root.history.length > 0);
                item.back.connect(() => PanelRouter.back(root.screen.name));
            }
        }
    }
}
