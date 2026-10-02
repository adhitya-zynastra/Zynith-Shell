import QtQuick
import qs.Common
import qs.Components
import qs.Services

// One mark per workspace on this output; the active one stretches into a bar. Clicking activates.
BarItem {
    id: root

    readonly property var sets: Workspaces.forScreen(screen)
    interactive: false
    pad: Metrics.s3
    spacing: Metrics.s2
    shown: sets.length > 0

    Repeater {
        model: root.sets

        delegate: Item {
            id: mark

            required property var modelData
            readonly property bool current: modelData.active
            readonly property real length: current ? 18 : modelData.urgent ? 8 : 6

            width: root.vertical ? 14 : length + 6
            height: root.vertical ? length + 6 : 14

            Rectangle {
                anchors.centerIn: parent
                width: root.vertical ? 4 : mark.length
                height: root.vertical ? mark.length : 4
                radius: 2
                color: mark.current ? Theme.accent : mark.modelData.urgent ? Theme.danger : Theme.inkFaint

                Behavior on width {
                    NumberAnimation {
                        duration: Motion.morph
                        easing.type: Motion.enterEasing
                    }
                }
                Behavior on height {
                    NumberAnimation {
                        duration: Motion.morph
                        easing.type: Motion.enterEasing
                    }
                }
                Behavior on color {
                    ColorAnimation {
                        duration: Motion.focus
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: if (mark.modelData.canActivate)
                    mark.modelData.activate()
            }
        }
    }
}
