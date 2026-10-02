import QtQuick
import qs.Common
import qs.Components

// Base for bar widgets: content laid out along the bar, a state layer, and a collapse when the widget
// has nothing to show (shown: false) so empty widgets take no room.
Item {
    id: root

    property bool vertical: false
    property var screen: null
    property var bar: null
    property bool shown: true
    property bool active: false
    property bool interactive: true
    property int pad: Metrics.s3
    property alias spacing: grid.spacing
    default property alias content: grid.data
    readonly property alias hovered: area.containsMouse

    signal clicked(var mouse)
    signal scrolled(int delta)

    readonly property real naturalLength: (vertical ? grid.implicitHeight : grid.implicitWidth) + pad * 2
    readonly property real cross: (bar?.thickness ?? Metrics.barThickness) - 8

    implicitWidth: vertical ? cross : (shown ? naturalLength : 0)
    implicitHeight: vertical ? (shown ? naturalLength : 0) : cross
    opacity: shown ? 1 : 0
    clip: true

    Behavior on implicitWidth {
        enabled: !root.vertical
        NumberAnimation {
            duration: Motion.morph
            easing.type: Motion.enterEasing
        }
    }
    Behavior on implicitHeight {
        enabled: root.vertical
        NumberAnimation {
            duration: Motion.morph
            easing.type: Motion.enterEasing
        }
    }
    Behavior on opacity {
        NumberAnimation {
            duration: root.shown ? Motion.contentIn : Motion.contentOut
            easing.type: root.shown ? Motion.standardEasing : Motion.exitEasing
        }
    }

    Interactive {
        id: area

        anchors.fill: parent
        visible: root.interactive
        radius: Metrics.radiusMd
        active: root.active
        onClicked: mouse => root.clicked(mouse)
        onWheel: wheel => root.scrolled(wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.angleDelta.x)
    }

    Grid {
        id: grid

        anchors.centerIn: parent
        columns: root.vertical ? 1 : 64
        spacing: Metrics.s2
        horizontalItemAlignment: Grid.AlignHCenter
        verticalItemAlignment: Grid.AlignVCenter
    }
}
