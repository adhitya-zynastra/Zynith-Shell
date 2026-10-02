import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import qs.Common
import qs.Components

// Status icons from apps. Click activates, right click opens the app's menu, middle click is the secondary action.
BarItem {
    id: root

    interactive: false
    shown: SystemTray.items.values.length > 0
    spacing: Metrics.s3

    Repeater {
        model: SystemTray.items

        delegate: Item {
            id: entry
            required property SystemTrayItem modelData
            width: 18
            height: 18

            // an icon name the theme lacks would draw Qt's checkerboard; those get a plain glyph instead
            readonly property string source: {
                const icon = entry.modelData.icon ?? "";
                if (icon.startsWith("image://icon/")) {
                    const name = icon.substring(13).split("?")[0];
                    return Quickshell.iconPath(name, true);
                }
                return icon;
            }
            IconImage {
                anchors.fill: parent
                visible: entry.source !== ""
                source: entry.source
                asynchronous: true
                opacity: area.containsMouse ? 1 : 0.85
            }
            Icon {
                anchors.centerIn: parent
                visible: entry.source === ""
                name: "apps"
                tone: "muted"
            }
            MouseArea {
                id: area
                anchors.fill: parent
                anchors.margins: -4
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                cursorShape: Qt.PointingHandCursor
                onClicked: mouse => {
                    if (mouse.button === Qt.MiddleButton) {
                        entry.modelData.secondaryActivate();
                    } else if (mouse.button === Qt.RightButton || entry.modelData.onlyMenu) {
                        if (entry.modelData.hasMenu) {
                            const p = entry.mapToItem(null, 0, entry.height);
                            entry.modelData.display(root.bar, p.x, p.y + 4);
                        }
                    } else {
                        entry.modelData.activate();
                    }
                }
            }
        }
    }
}
