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
    // room around the content along the bar: none, as the native bar (its widget_spacing separates widgets —
    // with 8 a side the rail's icons stood 44 px apart instead of the native 28); `widget_padding` on a widget
    // or its bar adds some
    property int pad: settings.widget_padding ?? bar?.spec?.widget_padding ?? 0
    property alias spacing: grid.spacing
    default property alias content: grid.data
    readonly property bool hovered: area.containsMouse
    property string tooltip: opt("tooltip") ?? ""

    // the reserved gestures, for the widget itself
    signal clicked(var mouse)
    signal scrolled(int delta)

    // ── styling the widget's content reads ──
    // the widget's own colour, else its capsule's foreground, else the bar's widget colour, else the theme's
    readonly property color ink: (opt("color") ?? "") !== "" ? Theme.colour(opt("color")) : capsule && (bar?.capsuleForeground ?? "") !== "" ? Theme.colour(bar.capsuleForeground) : (bar?.widgetColor ?? "") !== "" ? Theme.colour(bar.widgetColor) : Theme.ink
    readonly property color iconInk: (opt("icon_color") ?? "") !== "" ? Theme.colour(opt("icon_color")) : (bar?.widgetIconColor ?? "") !== "" && !(capsule && (bar?.capsuleForeground ?? "") !== "") ? Theme.colour(bar.widgetIconColor) : ink
    // label weight: the widget's, else the bar's (100–900)
    readonly property int weight: Number(opt("font_weight") ?? bar?.fontWeight ?? 400)
    readonly property string family: (opt("font_family") ?? "") !== "" ? opt("font_family") : (bar?.fontFamily ?? "") !== "" ? bar.fontFamily : Type.ui
    // the widget's own text size times its bar's
    readonly property real fontScale: (opt("font_scale") ?? 1) * (bar?.fontScale ?? 1)
    readonly property real sizeScale: (opt("scale") ?? 1) * (bar?.contentScale ?? 1)

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
        anchors.centerIn: parent
        // across the bar: capsule_thickness of it (the widget's, else the bar's; 1 fills)
        readonly property real across: (root.vertical ? parent.width : parent.height) * Math.max(0.1, Math.min(1, root.settings.capsule_thickness ?? root.bar?.capsuleThickness ?? 1)) - 2
        width: root.vertical ? across : parent.width - 2
        height: root.vertical ? parent.height - 2 : across
        radius: {
            const r = root.settings.capsule_radius ?? root.bar?.capsuleRadius;
            return r === undefined || r === "auto" || r < 0 ? Math.min(width, height) / 2 : r;
        }
        color: Theme.alpha(Theme.colour(root.settings.capsule_fill ?? root.bar?.capsuleFill ?? "surface_variant"), root.settings.capsule_opacity ?? root.bar?.capsuleOpacity ?? 0.5)
        readonly property string edgeColour: root.settings.capsule_border ?? root.bar?.capsuleBorder ?? ""
        border.width: edgeColour !== "" ? 1 : 0
        border.color: edgeColour !== "" ? Theme.colour(edgeColour) : "transparent"
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
        let action = BarWidgetTypes.action(type, settings, actions, gesture);
        // a click on what the pointer's rest just opened confirms it rather than closing it (as the native bar)
        if (gesture === "left" && hoverOpened && action.startsWith("panel-toggle "))
            action = "panel-open " + action.slice(13);
        hoverOpened = false;
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

        // the highlight reaches a little past an unpadded widget, so it frames the glyph rather than clips it
        Rectangle {
            anchors.fill: parent
            anchors.margins: -Math.max(0, 4 - root.pad)
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

    // the hover gesture: the pointer resting here for hover_delay runs it, once per visit
    readonly property string hoverAction: BarWidgetTypes.action(type, settings, actions, "hover")
    property bool hoverOpened: false
    Timer {
        id: hoverIntent
        interval: Math.max(0, root.opt("hover_delay") ?? 350)
        running: root.hovered && root.hoverAction !== "" && !root.hoverOpened
        onTriggered: root.restOpen()
    }
    // also run by a capsule group the pointer rests on (resting anywhere on the group counts)
    function restOpen(): void {
        if (hoverAction === "")
            return;
        hoverOpened = true;
        Actions.run(hoverAction.startsWith("panel-toggle ") ? "panel-open " + hoverAction.slice(13) : hoverAction, {
            screen: root.screen,
            bar: root.bar,
            item: root,
            widget: root.name
        });
    }
    // a tooltip, after the pointer has rested a moment
    property bool tipReady: false
    onHoveredChanged: if (!hovered) {
        tipReady = false;
        hoverOpened = false;
    }
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
