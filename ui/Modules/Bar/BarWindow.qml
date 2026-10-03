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
    // concave_edge_corners (with no edge margin): fillets where the bar meets the screen — at its ends on the
    // screen edge, or on its inner edge when it also reaches the screen's ends; those corners are square
    readonly property bool concave: spec.concave_edge_corners === true && margin === 0
    readonly property string concaveMode: anchorAt === "fill" && offset === 0 ? "inner" : "edge"
    // which of the pill's corners touch the screen edge (tl tr br bl)
    readonly property var edgeCorners: ({
            top: [0, 1],
            bottom: [3, 2],
            left: [0, 3],
            right: [1, 2]
        })[edge]
    readonly property var innerCorners: ({
            top: [3, 2],
            bottom: [0, 1],
            left: [1, 2],
            right: [0, 3]
        })[edge]
    readonly property var corners: {
        const own = [spec.radius_top_left, spec.radius_top_right, spec.radius_bottom_right, spec.radius_bottom_left];
        if (!concave && !own.some(v => v !== undefined))
            return null;
        const c = own.map(v => v ?? radius);
        if (concave)
            for (const i of (concaveMode === "edge" ? edgeCorners : innerCorners))
                c[i] = 0;
        return c;
    }
    // bar-wide defaults the widgets read
    readonly property real contentScale: spec.scale ?? 1
    readonly property int fontWeight: Number(spec.font_weight ?? 400)
    readonly property string widgetColor: spec.color ?? ""
    readonly property string widgetIconColor: spec.icon_color ?? ""
    readonly property var capsuleRadius: spec.capsule_radius
    readonly property string capsuleBorder: spec.capsule_border ?? ""
    readonly property string capsuleForeground: spec.capsule_foreground ?? ""
    readonly property real capsuleThickness: spec.capsule_thickness ?? 1
    // values under the glyphs of a vertical bar (volume, brightness, battery) in the data voice
    readonly property bool readouts: spec.readouts ?? true
    // how groups look unless a group says: rule (hairline ticks, no box) · capsule · plate
    readonly property string groupStyle: spec.group_style ?? "rule"
    // how far a panel opened from here tucks under the bar's edge (hides the seam)
    readonly property int panelOverlap: spec.panel_overlap ?? 0
    // "centred" against the whole output, or what other bars and docks leave of it
    readonly property string reference: spec.reference ?? "output"
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
    readonly property bool hides: visibility === "autohide" || visibility === "smart"
    readonly property bool panelHere: PanelRouter.openPanels[screen?.name ?? ""] !== undefined
    // the pointer on the bar, or on the edge strip that summons it; leaving lets it go after hide_delay_ms
    property bool held: false
    readonly property bool hovered: hover.hovered
    onHoveredChanged: {
        if (hovered) {
            letGo.stop();
            held = true;
        } else {
            letGo.restart();
        }
    }
    Timer {
        id: letGo
        interval: Math.max(0, win.spec.hide_delay_ms ?? 350)
        onTriggered: win.held = false
    }
    // a hidden bar shows itself for a moment when the workspace changes (the native show_on_workspace_switch)
    property bool peeking: false
    readonly property var activeWorkspace: Workspaces.forScreen(screen).find(w => w.active)?.id ?? -1
    onActiveWorkspaceChanged: if (hides && (spec.reveal_on_switch ?? true)) {
        peeking = true;
        peekEnd.restart();
    }
    Timer {
        id: peekEnd
        interval: Math.max(200, win.spec.reveal_on_switch_ms ?? 1200)
        onTriggered: win.peeking = false
    }
    readonly property bool wantsHidden: {
        if (panelHere || held || peeking)
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
    // how much of the edge summons a hidden bar: reveal_length along it, centred on the bar (0 = the bar's own
    // length), reveal_size deep. A bar that has shrunk to nothing still has its whole strip.
    readonly property int revealLength: hides ? Math.max(0, spec.reveal_length ?? 480) : 0
    readonly property int revealSize: Math.max(1, spec.reveal_size ?? 3)

    // Room for the shadow. Whatever part of it would fall off-screen is taken from the margins instead.
    readonly property int pad: ExperiencePolicy.shadows ? Metrics.shadowPad : 0
    // a bar that hides keeps its surface on the screen edge (the margin is inside it), so its summoning strip
    // is where the pointer stops
    readonly property int edgeGap: hides ? 0 : Math.max(0, margin - pad)
    readonly property int edgeInset: margin - edgeGap
    readonly property int alongGap: Math.max(0, offset - pad)
    readonly property int alongInset: anchorAt === "center" ? pad : offset - alongGap

    readonly property real contentLength: (vertical ? sections.implicitHeight : sections.implicitWidth) + padding * 2
    readonly property real screenLength: vertical ? (screen?.height ?? 0) : (screen?.width ?? 0)
    readonly property real pillLength: anchorAt === "fill" ? screenLength - offset * 2 : fixedLength > 0 ? fixedLength : Math.max(thickness, contentLength)

    WlrLayershell.namespace: "zynith-bar-" + (spec.id ?? "bar")
    WlrLayershell.layer: spec.layer === "overlay" ? WlrLayer.Overlay : spec.layer === "bottom" ? WlrLayer.Bottom : WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: reserve && visibility === "always" ? ExclusionMode.Normal : reference === "workspace" ? ExclusionMode.Auto : ExclusionMode.Ignore
    // margin_opposite: more reserved room on the inner side, for windows that ignore the zone's edge
    exclusiveZone: reserve && visibility === "always" ? thickness + margin + (spec.margin_opposite ?? 0) : 0
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
    readonly property int pillAlong: pillLength + alongInset + pad
    // wider than the bar when its summoning strip is longer; the extra is transparent and takes no input
    readonly property int alongSize: anchorAt === "fill" ? pillAlong : Math.max(pillAlong, Math.min(screenLength, revealLength))
    readonly property int alongExtra: alongSize - pillAlong
    implicitWidth: vertical ? crossSize : alongSize
    implicitHeight: vertical ? alongSize : crossSize

    // input follows where the bar is going, not where its animation is: hidden takes only the strip
    // (while it shows, its strip stays live too, or a pointer resting on the strip beside it would flicker it)
    mask: Region {
        item: win.wantsHidden ? strip : hitbox
        Region {
            item: win.hides && !win.wantsHidden ? strip : null
        }
    }
    // the bar's input shape, a plain item directly in the window: naming the pill (inside the scene, with its
    // slide transform) here left the bars taking no input at all — tested with a real pointer
    Item {
        id: hitbox
        x: scene.x + pill.x
        y: scene.y + pill.y
        width: pill.width
        height: pill.height
    }

    HoverHandler {
        id: hover
    }

    // where the pointer summons a hidden bar
    Item {
        id: strip
        readonly property real length: win.revealLength > 0 ? Math.min(win.vertical ? win.height : win.width, win.revealLength) : (win.vertical ? pill.height : pill.width)
        x: win.vertical ? (win.edge === "left" ? 0 : win.width - win.revealSize) : Math.max(0, Math.min(win.width - length, pill.x + pill.width / 2 - length / 2))
        y: win.vertical ? Math.max(0, Math.min(win.height - length, pill.y + pill.height / 2 - length / 2)) : (win.edge === "top" ? 0 : win.height - win.revealSize)
        width: win.vertical ? win.revealSize : length
        height: win.vertical ? length : win.revealSize
    }

    // the compositor blurs behind the bar only while it is there: a hidden bar must leave no frosted patch
    BlurRegion {
        window: win
        item: pill.presence > 0.02 ? pill : null
        radius: win.radius
    }

    // along the bar: at its anchor, the extra summoning room on the far side (both sides when centred)
    function alongPos(): real {
        if (anchorAt === "center")
            return alongInset + alongExtra / 2;
        return anchorAt === "end" ? pad + alongExtra : alongInset;
    }
    function pillX(): real {
        if (vertical)
            return edge === "left" ? edgeInset : pad;
        return alongPos();
    }
    function pillY(): real {
        if (!vertical)
            return edge === "top" ? edgeInset : pad;
        return alongPos();
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
            extent: margin + thickness - panelOverlap,
            // for diagnostics: where the bar and its summoning strip are, in screen coordinates
            hidden: wantsHidden,
            bar: [Math.round(windowScreenX() + pill.x), Math.round(windowScreenY() + pill.y), Math.round(pill.width), Math.round(pill.height)],
            strip: hides ? [Math.round(windowScreenX() + strip.x), Math.round(windowScreenY() + strip.y), Math.round(strip.width), Math.round(strip.height)] : null
        })
    onAnchorOriginChanged: PanelRouter.noteBar(spec.id ?? "", screen?.name ?? "", anchorOrigin)
    // for diagnostics: the bar's own pixels, nothing behind them
    Component.onCompleted: PanelRouter.barItems[(spec.id ?? "") + "@" + (screen?.name ?? "")] = scene

    // options: { open: open rather than toggle, history: where back goes }
    function openPanel(id: string, item: Item, context: string, options: var): void {
        const p = item.mapToItem(pill, item.width / 2, item.height / 2);
        const origin = {
            x: windowScreenX() + pill.x + p.x,
            y: windowScreenY() + pill.y + p.y,
            edge: edge,
            extent: margin + thickness - panelOverlap,
            context: context ?? "",
            history: options?.history ?? []
        };
        if (options?.open)
            PanelRouter.open(id, screen.name, origin);
        else
            PanelRouter.toggle(id, screen.name, origin);
    }

    // everything the bar draws, in one item (so it can be captured for diagnostics)
    Item {
        id: scene
        anchors.fill: parent

        // ── concave fillets ──
        Repeater {
            model: win.concave ? scene.fillets() : []
            delegate: ConcaveCorner {
                required property var modelData
                x: modelData.x
                y: modelData.y
                r: modelData.r
                solid: modelData.solid
                fill: Theme.alpha(Theme.glass, win.sheetOpacity)
                opacity: pill.presence
                transform: Translate {
                    x: win.edge === "left" ? -pill.away : win.edge === "right" ? pill.away : 0
                    y: win.edge === "top" ? -pill.away : win.edge === "bottom" ? pill.away : 0
                }
            }
        }
        function fillets(): var {
            const r = Math.max(0, Math.min(spec.concave_radius ?? radius, concaveMode === "edge" ? alongInset : pad));
            if (r < 1)
                return [];
            const px = pill.x, py = pill.y, pw = pill.width, ph = pill.height;
            const table = {
                top: { inner: [[px, py + ph, "tl"], [px + pw - r, py + ph, "tr"]], edge: [[px - r, py, "tr"], [px + pw, py, "tl"]] },
                bottom: { inner: [[px, py - r, "bl"], [px + pw - r, py - r, "br"]], edge: [[px - r, py + ph - r, "br"], [px + pw, py + ph - r, "bl"]] },
                left: { inner: [[px + pw, py, "tl"], [px + pw, py + ph - r, "bl"]], edge: [[px, py - r, "bl"], [px, py + ph, "tl"]] },
                right: { inner: [[px - r, py, "tr"], [px - r, py + ph - r, "br"]], edge: [[px + pw - r, py - r, "br"], [px + pw - r, py + ph, "tr"]] }
            };
            return table[edge][concaveMode].map(f => ({ x: f[0], y: f[1], solid: f[2], r: r }));
        }

        // ── contact shadow: depth at the seam while a panel opened from this bar is attached ──
        Rectangle {
            readonly property real depth: 12
            visible: win.spec.contact_shadow === true && opacity > 0
            opacity: win.panelHere ? pill.presence : 0
            Behavior on opacity {
                Anim {
                    role: "effects"
                }
            }
            x: win.vertical ? (win.edge === "left" ? pill.x + pill.width : pill.x - depth) : pill.x + pill.height / 2
            y: win.vertical ? pill.y + pill.width / 2 : (win.edge === "top" ? pill.y + pill.height : pill.y - depth)
            width: win.vertical ? depth : pill.width - pill.height
            height: win.vertical ? pill.height - pill.width : depth
            gradient: Gradient {
                orientation: win.vertical ? Gradient.Horizontal : Gradient.Vertical
                GradientStop {
                    position: 0
                    color: win.edge === "top" || win.edge === "left" ? Theme.alpha(Theme.shadow, 0.5) : "transparent"
                }
                GradientStop {
                    position: 1
                    color: win.edge === "top" || win.edge === "left" ? "transparent" : Theme.alpha(Theme.shadow, 0.5)
                }
            }
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
            visible: presence > 0.001
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
}
