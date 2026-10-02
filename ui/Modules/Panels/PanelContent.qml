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

    // the panel actually shown; lags panelId by one fade when navigating
    property string shownId: panelId
    property real fade: 1

    implicitHeight: loader.item?.implicitHeight ?? 0

    readonly property var panels: ({
            home: home,
            media: media,
            system: system,
            network: network,
            bluetooth: bluetooth
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

    Loader {
        id: loader

        width: parent.width
        opacity: root.fade
        sourceComponent: root.panels[root.shownId] ?? null
        onLoaded: {
            item.screen = Qt.binding(() => root.screen);
            item.visibleProgress = Qt.binding(() => root.visibleProgress);
            if (item.canGoBack !== undefined) {
                item.canGoBack = Qt.binding(() => root.history.length > 0);
                item.back.connect(() => PanelRouter.back(root.screen.name));
            }
        }
    }
}
