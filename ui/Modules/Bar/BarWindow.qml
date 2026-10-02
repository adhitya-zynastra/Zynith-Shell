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
    readonly property real radius: spec.radius ?? thickness / 2

    // Room for the shadow. Whatever part of it would fall off-screen is taken from the margins instead.
    readonly property int pad: ExperiencePolicy.shadows ? Metrics.shadowPad : 0
    readonly property int edgeGap: Math.max(0, margin - pad)
    readonly property int edgeInset: margin - edgeGap
    readonly property int alongGap: Math.max(0, offset - pad)
    readonly property int alongInset: anchorAt === "center" ? pad : offset - alongGap

    readonly property real contentLength: (vertical ? sections.implicitHeight : sections.implicitWidth) + Metrics.s3 * 2
    readonly property real screenLength: vertical ? (screen?.height ?? 0) : (screen?.width ?? 0)
    readonly property real pillLength: anchorAt === "fill" ? screenLength - offset * 2 : Math.max(thickness, contentLength)

    WlrLayershell.namespace: "zynith-bar-" + (spec.id ?? "bar")
    WlrLayershell.layer: spec.layer === "overlay" ? WlrLayer.Overlay : spec.layer === "bottom" ? WlrLayer.Bottom : WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: reserve ? ExclusionMode.Normal : ExclusionMode.Ignore
    exclusiveZone: reserve ? thickness + margin : 0
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
        item: pill
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
    function openPanel(id: string, item: Item): void {
        const p = item.mapToItem(pill, item.width / 2, item.height / 2);
        PanelRouter.toggle(id, screen.name, {
            x: windowScreenX() + pill.x + p.x,
            y: windowScreenY() + pill.y + p.y,
            edge: edge,
            extent: margin + thickness
        });
    }

    Glass {
        id: pill

        x: win.pillX()
        y: win.pillY()
        width: win.vertical ? win.thickness : win.pillLength
        height: win.vertical ? win.pillLength : win.thickness
        radius: win.radius
        raised: true

        // arrive from the edge on start
        opacity: 0
        Component.onCompleted: opacity = 1
        Behavior on opacity {
            NumberAnimation {
                duration: Motion.reveal
                easing.type: Motion.enterEasing
            }
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

        BarSections {
            id: sections

            anchors.fill: parent
            anchors.margins: Metrics.s1
            bar: win
            fill: win.anchorAt === "fill"
        }
    }
}
