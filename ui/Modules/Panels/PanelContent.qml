import QtQuick
import qs.Common

// Picks the panel by id. New panels register here.
Item {
    id: root

    property string panelId: ""
    property var screen: null
    property real visibleProgress: 1

    implicitHeight: loader.item?.implicitHeight ?? 0

    readonly property var panels: ({
            home: home
        })

    Component {
        id: home
        HomePanel {}
    }

    Loader {
        id: loader

        width: parent.width
        sourceComponent: root.panels[root.panelId] ?? null
        onLoaded: {
            item.screen = Qt.binding(() => root.screen);
            item.visibleProgress = Qt.binding(() => root.visibleProgress);
        }
    }
}
