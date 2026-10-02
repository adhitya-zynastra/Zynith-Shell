import QtQuick
import qs.Common
import qs.Components
import qs.Services

// Base for bar widgets. What it shows comes from its settings (BarWidgetTypes defaults, then the bar's
// [widget.<name>] table); what a click, a scroll or a thumb button does comes from its actions, run through
// Actions — never from the widget's own code, except the gestures a kind reserves (a workspace pill's left
// click, a tray item's menu). Common styling: colour, icon colour, font, text size, overall size, a capsule.
// A widget with nothing to show collapses (shown: false) so it takes no room.
Item {
    id: root

    property bool vertical: false
    property var screen: null
    property var bar: null
    // what this is: its kind, its name in the bar's list, its settings and actions
    property string type: ""
    property string name: type
    property var settings: ({})
    property var actions: ({})
    function opt(key: string): var {
        return BarWidgetTypes.value(type, settings, key);
    }

    property bool shown: true
    property bool active: false
    property bool interactive: opt("interactive") !== false
    property int pad: Metrics.s3
    property alias spacing: grid.spacing
    default property alias content: grid.data
    readonly property bool hovered: area.containsMouse
    property string tooltip: opt("tooltip") ?? ""

    // the reserved gestures, for the widget itself
    signal clicked(var mouse)
    signal scrolled(int delta)

    // ── styling the widget's content reads ──
    readonly property color ink: (opt("color") ?? "") !== "" ? Theme.colour(opt("color")) : Theme.ink
    readonly property color iconInk: (opt("icon_color") ?? "") !== "" ? Theme.colour(opt("icon_color")) : ink
    readonly property string family: (opt("font_family") ?? "") !== "" ? opt("font_family") : (bar?.fontFamily ?? "") !== "" ? bar.fontFamily : Type.ui
    // the widget's own text size times its bar's
    readonly property real fontScale: (opt("font_scale") ?? 1) * (bar?.fontScale ?? 1)
    readonly property real sizeScale: opt("scale") ?? 1

    // a capsule: the widget's own setting, else the bar's default
    readonly property bool capsule: settings.capsule !== undefined ? settings.capsule === true : (bar?.widgetCapsule ?? false)

    readonly property real naturalLength: ((vertical ? grid.implicitHeight : grid.implicitWidth) * sizeScale) + pad * 2 + (capsule ? capsulePad * 2 : 0)
    readonly property real cross: (bar?.thickness ?? Metrics.barThickness) - 8
    readonly property real capsulePad: settings.capsule_padding ?? bar?.capsulePadding ?? 0

    implicitWidth: vertical ? cross : (shown ? naturalLength : 0)
    implicitHeight: vertical ? (shown ? naturalLength : 0) : cross
    opacity: shown ? 1 : 0
    visible: implicitWidth > 0.5 && implicitHeight > 0.5

    Behavior on implicitWidth {
        enabled: !root.vertical
        Anim {
            role: "spatialFast"
        }
    }
    Behavior on implicitHeight {
        enabled: root.vertical
        Anim {
            role: "spatialFast"
        }
    }
    Behavior on opacity {
        Anim {
            role: root.shown ? "effects" : "exit"
        }
    }

    Rectangle {
        visible: root.capsule
        anchors.fill: parent
        anchors.margins: 1
        radius: {
            const r = root.opt("capsule_radius");
            return r === undefined || r === "auto" || r < 0 ? Math.min(width, height) / 2 : r;
        }
        color: Theme.alpha(Theme.colour(root.settings.capsule_fill ?? root.bar?.capsuleFill ?? "surface_variant"), root.settings.capsule_opacity ?? root.bar?.capsuleOpacity ?? 0.5)
        border.width: (root.settings.capsule_border ?? "") !== "" ? 1 : 0
        border.color: Theme.colour(root.settings.capsule_border ?? "outline")
    }

    // which gesture a button or a wheel step is
    function gestureOf(button: int): string {
        return button === Qt.RightButton ? "right" : button === Qt.MiddleButton ? "middle" : button === Qt.BackButton ? "back" : button === Qt.ForwardButton ? "forward" : "left";
    }
    function perform(gesture: string, event: var): void {
        if (BarWidgetTypes.reserved(type, gesture)) {
            if (gesture.startsWith("scroll"))
                scrolled(gesture === "scroll_up" || gesture === "scroll_left" ? 1 : -1);
            else
                clicked(event);
            return;
        }
        const action = BarWidgetTypes.action(type, settings, actions, gesture);
        if (action !== "")
            Actions.run(action, {
                screen: root.screen,
                bar: root.bar,
                item: root,
                widget: root.name
            });
        else if (!gesture.startsWith("scroll"))
            clicked(event);
        else
            scrolled(gesture === "scroll_up" ? 1 : -1);
    }

    MouseArea {
        id: area
        anchors.fill: parent
        visible: root.interactive
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton | Qt.BackButton | Qt.ForwardButton
        onClicked: mouse => root.perform(root.gestureOf(mouse.button), mouse)
        // a wheel turns in notches; a touchpad's small steps add up to one
        property real rest: 0
        onWheel: wheel => {
            const horizontal = Math.abs(wheel.angleDelta.x) > Math.abs(wheel.angleDelta.y);
            rest += horizontal ? wheel.angleDelta.x : wheel.angleDelta.y;
            while (Math.abs(rest) >= 120) {
                const up = rest > 0;
                root.perform(horizontal ? (up ? "scroll_left" : "scroll_right") : (up ? "scroll_up" : "scroll_down"), wheel);
                rest -= up ? 120 : -120;
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: Metrics.radiusMd
            color: area.pressed ? Theme.press : root.active ? Theme.accentSoft : area.containsMouse && (root.bar?.hoverHighlight ?? true) ? Theme.hover : "transparent"
            Behavior on color {
                ColorAnim {}
            }
        }
    }

    Grid {
        id: grid

        anchors.centerIn: parent
        columns: root.vertical ? 1 : 64
        spacing: Metrics.s2
        horizontalItemAlignment: Grid.AlignHCenter
        verticalItemAlignment: Grid.AlignVCenter
        scale: root.sizeScale
    }

    // a tooltip, after the pointer has rested a moment
    property bool tipReady: false
    onHoveredChanged: if (!hovered)
        tipReady = false
    Timer {
        interval: 600
        running: root.hovered && root.tooltip !== "" && !root.tipReady
        onTriggered: root.tipReady = true
    }
    Rectangle {
        visible: root.tipReady && root.hovered && root.tooltip !== ""
        z: 10
        x: root.vertical ? (root.bar?.edge === "right" ? -width - 8 : root.width + 8) : (root.width - width) / 2
        y: root.vertical ? (root.height - height) / 2 : (root.bar?.edge === "bottom" ? -height - 8 : root.height + 8)
        width: tipText.implicitWidth + Metrics.s4
        height: tipText.implicitHeight + Metrics.s2
        radius: 8
        color: Theme.alpha(Theme.base, 0.92)
        Label {
            id: tipText
            anchors.centerIn: parent
            role: "caption"
            text: root.tooltip
        }
    }
}
