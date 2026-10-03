import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Components
import qs.Services
import qs.Widgets

// One bar on one output. Geometry comes from the bar spec: an edge (top/bottom/left/right), an anchor
// along it (start/center/end/fill), an offset from the anchored corner, a margin from the screen edge.
PanelWindow {
    id: win

    required property var spec
    required property var modelData

    screen: modelData

    readonly property string edge: spec.edge ?? "top"
    readonly property string anchorAt: spec.anchor ?? "center"
    readonly property bool vertical: edge === "left" || edge === "right"
    readonly property int thickness: spec.thickness ?? Metrics.barThickness
    readonly property int margin: spec.margin ?? 0
    readonly property int offset: anchorAt === "center" ? 0 : (spec.offset ?? 0)
    readonly property bool reserve: spec.reserve ?? false
    // style: keys left out follow appearance.toml
    readonly property real radius: (spec.radius ?? -1) >= 0 ? spec.radius * Metrics.radiusScale : thickness / 2
    readonly property real sheetOpacity: (spec.opacity ?? 0) > 0 ? Math.min(1, spec.opacity) : Theme.glassAlpha
    readonly property bool border: spec.border ?? true
    readonly property int spacingOverride: spec.spacing ?? -1
    readonly property int padding: spec.padding ?? Metrics.s3
    // a fixed length along the edge (0 = fit the widgets)
    readonly property int fixedLength: spec.length ?? 0
    // per-corner radii (px), as the native bars had them; left out, the radius above
    readonly property var corners: [spec.radius_top_left, spec.radius_top_right, spec.radius_bottom_right, spec.radius_bottom_left].some(v => v !== undefined) ? [spec.radius_top_left ?? radius, spec.radius_top_right ?? radius, spec.radius_bottom_right ?? radius, spec.radius_bottom_left ?? radius] : null
    readonly property string borderColor: spec.border_color ?? ""
    readonly property real borderWidth: spec.border_width ?? -1
    readonly property bool shadow: spec.shadow ?? true
    // what the widgets on this bar default to
    readonly property string fontFamily: spec.font_family ?? ""
    readonly property real fontScale: spec.font_scale ?? 1
    // what a click or a scroll does on the bar's empty space ([bar.actions]); natively, right click opened the
    // Control Center
    function deadZoneAction(gesture: string): string {
        const own = spec.actions ?? {};
        if (own[gesture] !== undefined)
            return own[gesture];
        return gesture === "right" ? "panel-toggle control-center home" : "";
    }
    readonly property bool hoverHighlight: spec.hover_highlight ?? true
    readonly property bool widgetCapsule: spec.capsule ?? false
    readonly property string capsuleFill: spec.capsule_fill ?? "surface_variant"
    readonly property real capsuleOpacity: spec.capsule_opacity ?? 0.5
    readonly property real capsulePadding: spec.capsule_padding ?? 0
    // capsule groups: this bar's own ([[bar.group]]), then the shared ones ([[group]])
    function groupFor(id: string): var {
        return (spec.group ?? []).find(g => g.id === id) ?? Config.barGroups.find(g => g.id === id) ?? null;
    }

    // always | autohide (reveal at the edge) | smart (hidden while the active workspace has windows)
    readonly property string visibility: spec.visibility ?? "always"
    readonly property bool panelHere: PanelRouter.openPanels[screen?.name ?? ""] !== undefined
    readonly property bool hovered: hover.hovered
    readonly property bool wantsHidden: {
        if (panelHere || hovered)
            return false;
        if (visibility === "autohide")
            return true;
        if (visibility === "smart")
            return Workspaces.occupied(screen?.name ?? "") && !Workspaces.overviewOpen;
        return false;
    }
    // 1 = in place, 0 = slid away
    property real shown: wantsHidden ? 0 : 1
    Behavior on shown {
        NumberAnimation {
            duration: win.wantsHidden ? Motion.dismiss : Motion.reveal
            easing.type: win.wantsHidden ? Motion.exitEasing : Motion.enterEasing
        }
    }
    // a bar that is fully away renders nothing at all
    updatesEnabled: shown > 0

    // Room for the shadow. Whatever part of it would fall off-screen is taken from the margins instead.
    readonly property int pad: ExperiencePolicy.shadows ? Metrics.shadowPad : 0
    readonly property int edgeGap: Math.max(0, margin - pad)
    readonly property int edgeInset: margin - edgeGap
    readonly property int alongGap: Math.max(0, offset - pad)
    readonly property int alongInset: anchorAt === "center" ? pad : offset - alongGap

    readonly property real contentLength: (vertical ? sections.implicitHeight : sections.implicitWidth) + padding * 2
    readonly property real screenLength: vertical ? (screen?.height ?? 0) : (screen?.width ?? 0)
    readonly property real pillLength: anchorAt === "fill" ? screenLength - offset * 2 : fixedLength > 0 ? fixedLength : Math.max(thickness, contentLength)

    WlrLayershell.namespace: "zynith-bar-" + (spec.id ?? "bar")
    WlrLayershell.layer: spec.layer === "overlay" ? WlrLayer.Overlay : spec.layer === "bottom" ? WlrLayer.Bottom : WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: reserve && visibility === "always" ? ExclusionMode.Normal : ExclusionMode.Ignore
    exclusiveZone: reserve && visibility === "always" ? thickness + margin : 0
    color: "transparent"

    anchors {
        top: edge === "top" || (vertical && (anchorAt === "start" || anchorAt === "fill"))
        bottom: edge === "bottom" || (vertical && (anchorAt === "end" || anchorAt === "fill"))
        left: edge === "left" || (!vertical && (anchorAt === "start" || anchorAt === "fill"))
        right: edge === "right" || (!vertical && (anchorAt === "end" || anchorAt === "fill"))
    }
    margins {
        top: edge === "top" ? edgeGap : vertical && anchorAt !== "end" && anchorAt !== "center" ? alongGap : 0
        bottom: edge === "bottom" ? edgeGap : vertical && (anchorAt === "end" || anchorAt === "fill") ? alongGap : 0
        left: edge === "left" ? edgeGap : !vertical && anchorAt !== "end" && anchorAt !== "center" ? alongGap : 0
        right: edge === "right" ? edgeGap : !vertical && (anchorAt === "end" || anchorAt === "fill") ? alongGap : 0
    }

    // near = the screen edge / anchored corner side, far = the opposite side
    readonly property int crossSize: thickness + edgeInset + pad
    readonly property int alongSize: pillLength + alongInset + pad
    implicitWidth: vertical ? crossSize : alongSize
    implicitHeight: vertical ? alongSize : crossSize

    mask: Region {
        item: win.shown > 0.01 ? pill : strip
    }

    HoverHandler {
        id: hover
    }

    // where the pointer summons a hidden bar
    Item {
        id: strip
        x: win.vertical ? (win.edge === "left" ? 0 : win.width - 3) : pill.x
        y: win.vertical ? pill.y : (win.edge === "top" ? 0 : win.height - 3)
        width: win.vertical ? 3 : pill.width
        height: win.vertical ? pill.height : 3
    }

    BlurRegion {
        window: win
        item: pill
        radius: win.radius
    }

    function pillX(): real {
        if (vertical)
            return edge === "left" ? edgeInset : pad;
        return anchorAt === "end" ? pad : alongInset;
    }
    function pillY(): real {
        if (!vertical)
            return edge === "top" ? edgeInset : pad;
        return anchorAt === "end" ? pad : alongInset;
    }

    // Where the pill sits on the screen, so panels can grow out of the widget that opened them.
    function windowScreenX(): real {
        const w = screen?.width ?? 0;
        if (edge === "left")
            return edgeGap;
        if (edge === "right")
            return w - width - edgeGap;
        return anchorAt === "end" ? w - width - alongGap : anchorAt === "center" ? (w - width) / 2 : alongGap;
    }
    function windowScreenY(): real {
        const h = screen?.height ?? 0;
        if (edge === "top")
            return edgeGap;
        if (edge === "bottom")
            return h - height - edgeGap;
        return anchorAt === "end" ? h - height - alongGap : anchorAt === "center" ? (h - height) / 2 : alongGap;
    }
    // where a Control Panel opened from nowhere (a key) attaches, when [control_panel] anchor_bar names this bar
    readonly property var anchorOrigin: ({
            x: windowScreenX() + pill.x + pill.width / 2,
            y: windowScreenY() + pill.y + pill.height / 2,
            edge: edge,
            extent: margin + thickness
        })
    onAnchorOriginChanged: PanelRouter.noteBar(spec.id ?? "", screen?.name ?? "", anchorOrigin)

    // options: { open: open rather than toggle, history: where back goes }
    function openPanel(id: string, item: Item, context: string, options: var): void {
        const p = item.mapToItem(pill, item.width / 2, item.height / 2);
        const origin = {
            x: windowScreenX() + pill.x + p.x,
            y: windowScreenY() + pill.y + p.y,
            edge: edge,
            extent: margin + thickness,
            context: context ?? "",
            history: options?.history ?? []
        };
        if (options?.open)
            PanelRouter.open(id, screen.name, origin);
        else
            PanelRouter.toggle(id, screen.name, origin);
    }

    Glass {
        id: pill

        x: win.pillX()
        y: win.pillY()
        width: win.vertical ? win.thickness : win.pillLength
        height: win.vertical ? win.pillLength : win.thickness
        radius: win.radius
        corners: win.corners
        raised: win.shadow
        fill: Theme.alpha(Theme.glass, win.sheetOpacity)
        edge: win.border
        edgeColor: win.borderColor
        edgeWidth: win.borderWidth

        // slide toward the screen edge when hidden; arrive from it on start
        property real arrived: 0
        Component.onCompleted: arrived = 1
        Behavior on arrived {
            NumberAnimation {
                duration: Motion.reveal
                easing.type: Motion.enterEasing
            }
        }
        readonly property real presence: arrived * win.shown
        readonly property real away: (1 - presence) * (win.thickness + win.margin + 4)
        opacity: presence
        transform: Translate {
            x: win.edge === "left" ? -pill.away : win.edge === "right" ? pill.away : 0
            y: win.edge === "top" ? -pill.away : win.edge === "bottom" ? pill.away : 0
        }
        Behavior on width {
            enabled: !win.vertical && win.anchorAt !== "fill"
            NumberAnimation {
                duration: Motion.morph
                easing.type: Motion.enterEasing
            }
        }
        Behavior on height {
            enabled: win.vertical && win.anchorAt !== "fill"
            NumberAnimation {
                duration: Motion.morph
                easing.type: Motion.enterEasing
            }
        }

        // the bar's empty space: under the widgets, so it only sees what they let through
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton | Qt.BackButton | Qt.ForwardButton
            property real rest: 0
            onClicked: mouse => {
                const g = mouse.button === Qt.RightButton ? "right" : mouse.button === Qt.MiddleButton ? "middle" : mouse.button === Qt.BackButton ? "back" : mouse.button === Qt.ForwardButton ? "forward" : "left";
                Actions.run(win.deadZoneAction(g), {
                    screen: win.screen
                });
            }
            onWheel: wheel => {
                const horizontal = Math.abs(wheel.angleDelta.x) > Math.abs(wheel.angleDelta.y);
                rest += horizontal ? wheel.angleDelta.x : wheel.angleDelta.y;
                while (Math.abs(rest) >= 120) {
                    const up = rest > 0;
                    Actions.run(win.deadZoneAction(horizontal ? (up ? "scroll_left" : "scroll_right") : (up ? "scroll_up" : "scroll_down")), {
                        screen: win.screen
                    });
                    rest -= up ? 120 : -120;
                }
            }
        }

        BarSections {
            id: sections

            anchors.fill: parent
            anchors.margins: Metrics.s1
            bar: win
            fill: win.anchorAt === "fill"
        }
    }
}
