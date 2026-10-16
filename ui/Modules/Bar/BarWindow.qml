import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Components
import qs.Services
import qs.Widgets
import "../../Common/BarModel.js" as BarModel

// One bar on one output. Geometry comes from the bar spec: an edge (top/bottom/left/right), an anchor
// along it (start/center/end/fill), an offset from the anchored corner, a margin from the screen edge.
PanelWindow {
    id: win

    required property var spec
    required property var modelData

    screen: modelData

    // a value bars.toml got wrong (a typo, a word from another version, a string for a number) falls back to
    // its default and is named in the log, instead of laying the bar out from nonsense
    function oneOf(key: string, allowed: var, fallback: string): string {
        const v = spec[key];
        if (v === undefined || allowed.includes(v))
            return v ?? fallback;
        console.warn(`zynith: bar "${spec.id ?? "?"}": ${key} = ${JSON.stringify(v)} is not one of ${allowed.join(", ")}; using ${fallback}`);
        return fallback;
    }
    function number(key: string, fallback: real, least: real): real {
        const v = spec[key];
        if (v === undefined)
            return fallback;
        if (typeof v === "number" && isFinite(v) && v >= least)
            return v;
        console.warn(`zynith: bar "${spec.id ?? "?"}": ${key} = ${JSON.stringify(v)} is not a number of at least ${least}; using ${fallback}`);
        return fallback;
    }
    readonly property string edge: oneOf("edge", ["top", "bottom", "left", "right"], "top")
    readonly property string anchorAt: oneOf("anchor", ["start", "center", "end", "fill"], "center")
    readonly property bool vertical: edge === "left" || edge === "right"
    readonly property int thickness: number("thickness", Metrics.barThickness, 8)
    readonly property int margin: number("margin", 0, 0)
    readonly property int offset: anchorAt === "center" ? 0 : number("offset", 0, 0)
    readonly property bool reserve: spec.reserve ?? false
    // style: keys left out follow appearance.toml
    readonly property real radius: (spec.radius ?? -1) >= 0 ? spec.radius * Metrics.radiusScale : thickness / 2
    // a bar's own opacity applies to Glass and Blur; Solid is opaque by definition (the global style wins)
    readonly property real sheetOpacity: !Material.solid && (spec.opacity ?? 0) > 0 ? Math.min(1, spec.opacity) : Theme.glassAlpha
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
    // every corner as drawn (BarModel.cornerRadii: the one rule the sheet, its blur and its shadow share)
    readonly property var corners: BarModel.cornerRadii(spec, {
        w: pill.width,
        h: pill.height
    }, Metrics.radiusScale, joinProgress > 0 ? Object.assign({}, join, {
        progress: joinProgress
    }) : null)
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
    readonly property bool readouts: spec.readouts ?? false
    // how groups look unless a group says: rule (hairline ticks, no box) · capsule · plate
    readonly property string groupStyle: spec.group_style ?? "capsule"
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
    readonly property string visibility: oneOf("visibility", ["always", "smart", "autohide"], "always")
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
    // Room for the shadow: as far as it actually reaches (Glass.shadowExtent). A fixed 18 px left the last few
    // pixels of a 24 px shadow cut off by the window's square edge — a sharp-cornered rectangle around the bar.
    // Whatever part of it would fall off-screen is taken from the margins instead.
    // The concave fillets get their own room (BarModel.edgeRoom): with shadows paused they keep their shape.
    readonly property int pad: BarModel.edgeRoom({
        shadows: Material.shadows,
        shadow: shadow,
        shadowExtent: pill.shadowExtent,
        concave: concave,
        concaveRadius: spec.concave_radius ?? radius
    })
    // a bar that hides keeps its surface on the screen edge (the margin is inside it), so its summoning strip
    // is where the pointer stops
    readonly property int edgeGap: hides ? 0 : Math.max(0, margin - pad)
    readonly property int edgeInset: margin - edgeGap
    readonly property int alongGap: Math.max(0, offset - pad)
    readonly property int alongInset: anchorAt === "center" ? pad : offset - alongGap

    readonly property real contentLength: (vertical ? sections.implicitHeight : sections.implicitWidth) + padding * 2
    readonly property real screenLength: vertical ? (screen?.height ?? 0) : (screen?.width ?? 0)
    // the stretch of the edge it is laid out along: the whole edge, or (reference = workspace) what the bars on
    // the neighbouring edges keep for themselves leaves of it. rangeStart / rangeEnd: the room left at either end.
    readonly property var reserved: BarModel.reservations(Config.bars, screen?.name ?? "")
    readonly property var range: BarModel.alongRange(spec, screenLength, reserved)
    readonly property real rangeStart: range[0]
    readonly property real rangeEnd: Math.max(0, screenLength - range[1])
    // centred in a stretch that is not the whole edge: the compositor can only centre on the whole output, so the
    // window is placed from the start side instead
    readonly property bool centredInRange: anchorAt === "center" && rangeStart !== rangeEnd
    readonly property real pillLength: anchorAt === "fill" ? (range[1] - range[0]) - offset * 2 : fixedLength > 0 ? fixedLength : Math.max(thickness, contentLength)

    WlrLayershell.namespace: "zynith-bar-" + (spec.id ?? "bar")
    WlrLayershell.layer: spec.layer === "overlay" ? WlrLayer.Overlay : spec.layer === "bottom" ? WlrLayer.Bottom : WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    // Bars never reserve room themselves: the compositor stacks the zones of surfaces on one edge, so three bars
    // side by side on the top edge would each have been pushed below the one before. The room is kept by one
    // EdgeReserve surface per output and edge, as deep as the deepest bar there that keeps windows clear
    // (BarModel.reservations); every bar is placed against the whole output and keeps clear of its neighbours'
    // edges itself (reference = workspace).
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    // along the edge: anchored at the start side (start, fill, or centred in a stretch), the end side (end, fill)
    readonly property bool startAnchored: anchorAt === "start" || anchorAt === "fill" || centredInRange
    readonly property bool endAnchored: anchorAt === "end" || anchorAt === "fill"
    // the window's distance from the start / end of the edge
    readonly property real startMargin: centredInRange ? Math.round(rangeStart + (range[1] - range[0] - alongSize) / 2) : alongGap + rangeStart
    readonly property real endMargin: alongGap + rangeEnd
    anchors {
        top: edge === "top" || (vertical && startAnchored)
        bottom: edge === "bottom" || (vertical && endAnchored)
        left: edge === "left" || (!vertical && startAnchored)
        right: edge === "right" || (!vertical && endAnchored)
    }
    margins {
        top: edge === "top" ? edgeGap : vertical && startAnchored ? startMargin : 0
        bottom: edge === "bottom" ? edgeGap : vertical && endAnchored ? endMargin : 0
        left: edge === "left" ? edgeGap : !vertical && startAnchored ? startMargin : 0
        right: edge === "right" ? edgeGap : !vertical && endAnchored ? endMargin : 0
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
    // The pointer anywhere on the bar that opened the hover panel holds it, so moving from one icon to the next
    // hands the panel over (it reshapes into the next one) instead of closing in the gap between them and
    // opening again from nothing, whatever the close delay.
    readonly property var openEntry: PanelRouter.openPanels[screen?.name ?? ""] ?? null
    readonly property bool holdsHover: hover.hovered && (openEntry?.transient ?? false) && (openEntry?.barId ?? "") === (spec.id ?? "")
    onHoldsHoverChanged: PanelRouter.hold(screen?.name ?? "", "bar:" + (spec.id ?? ""), holdsHover)

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
        // blur = false: this bar never asks for it (the profile can still turn every blur off)
        item: pill.presence > 0.02 && win.spec.blur !== false ? pill : null
        // the sheet's corners exactly as drawn: a blur region with one radius stood out past the corners that were
        // rounder than it, a square frosted patch most visible while a workspace slid behind the bar
        corners: pill.drawnCorners
        // and the fillets where it flows into the screen edge, which are part of the same surface
        extra: win.concave && pill.presence > 0.98 ? scene.fillets().map(f => ({
                    x: f.x,
                    y: f.y,
                    w: f.r,
                    h: f.r,
                    cutX: (f.solid === "tr" || f.solid === "br" ? f.x : f.x + f.r) - f.r,
                    cutY: (f.solid === "bl" || f.solid === "br" ? f.y : f.y + f.r) - f.r,
                    cut: 2 * f.r
                })) : []
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
        return anchorAt === "end" ? w - width - endMargin : anchorAt === "center" && !centredInRange ? (w - width) / 2 : startMargin;
    }
    function windowScreenY(): real {
        const h = screen?.height ?? 0;
        if (edge === "top")
            return edgeGap;
        if (edge === "bottom")
            return h - height - edgeGap;
        return anchorAt === "end" ? h - height - endMargin : anchorAt === "center" && !centredInRange ? (h - height) / 2 : startMargin;
    }
    // how far into the screen the bar reaches, measured from the pill as drawn: where an attached panel meets it
    // exactly (panel_overlap, a floating panel's gap or overlap, does not apply to a joint)
    function reach(): real {
        const x0 = windowScreenX() + pill.x, y0 = windowScreenY() + pill.y;
        const r = edge === "left" ? x0 + pill.width : edge === "right" ? (screen?.width ?? 0) - x0 : edge === "top" ? y0 + pill.height : (screen?.height ?? 0) - y0;
        return Math.max(0, r);
    }
    // the pill's extent along its edge, in screen coordinates: where a panel can join it
    function barSpan(): var {
        return vertical ? [windowScreenY() + pill.y, windowScreenY() + pill.y + pill.height] : [windowScreenX() + pill.x, windowScreenX() + pill.x + pill.width];
    }
    // a panel joined to this bar (PanelSurface publishes it): the pill squares the corners it shares with it,
    // as the panel grows, so the two read as one surface
    readonly property var join: PanelRouter.joins[(spec.id ?? "") + "@" + (screen?.name ?? "")] ?? null
    readonly property real joinProgress: join?.progress ?? 0

    // where a Control Panel opened from nowhere (a key) attaches, when [control_panel] anchor_bar names this bar
    readonly property var anchorOrigin: ({
            x: windowScreenX() + pill.x + pill.width / 2,
            y: windowScreenY() + pill.y + pill.height / 2,
            edge: edge,
            extent: reach() - panelOverlap,
            reach: reach(),
            // what an attached panel needs to be one surface with the bar: its fill, its span along the edge
            fillOpacity: sheetOpacity,
            // the bar's own opacity setting (0: none), so a joined panel resolves its fill live with the bar's rule
            barOpacity: spec.opacity ?? 0,
            barSpan: barSpan(),
            barId: spec.id ?? "",
            // for diagnostics: the bar window's own position on the output (to composite captures)
            win: [Math.round(windowScreenX()), Math.round(windowScreenY())],
            // the room it keeps windows out of (its exclusive zone): the output's work area is what is left
            reserved: reserve && visibility === "always" ? thickness + margin + (spec.margin_opposite ?? 0) : 0,
            // for diagnostics: where the bar and its summoning strip are, in screen coordinates
            hidden: wantsHidden,
            bar: [Math.round(windowScreenX() + pill.x), Math.round(windowScreenY() + pill.y), Math.round(pill.width), Math.round(pill.height)],
            strip: hides ? [Math.round(windowScreenX() + strip.x), Math.round(windowScreenY() + strip.y), Math.round(strip.width), Math.round(strip.height)] : null
        })
    onAnchorOriginChanged: PanelRouter.noteBar(spec.id ?? "", screen?.name ?? "", anchorOrigin)
    Component.onDestruction: {
        delete PanelRouter.barItems[(spec.id ?? "") + "@" + (screen?.name ?? "")];
        PanelRouter.forgetBar(spec.id ?? "", screen?.name ?? "");
        PanelRouter.hold(screen?.name ?? "", "bar:" + (spec.id ?? ""), false);
    }
    // for diagnostics: the bar's own pixels, nothing behind them
    Component.onCompleted: PanelRouter.barItems[(spec.id ?? "") + "@" + (screen?.name ?? "")] = scene

    // options: { open: open rather than toggle, history: where back goes }
    function openPanel(id: string, item: Item, context: string, options: var): void {
        const p = item.mapToItem(pill, item.width / 2, item.height / 2);
        const origin = {
            x: windowScreenX() + pill.x + p.x,
            y: windowScreenY() + pill.y + p.y,
            edge: edge,
            extent: reach() - panelOverlap,
            reach: reach(),
            fillOpacity: sheetOpacity,
            // the bar's own opacity setting (0: none), so a joined panel resolves its fill live with the bar's rule
            barOpacity: spec.opacity ?? 0,
            barSpan: barSpan(),
            barId: spec.id ?? "",
            itemSpan: vertical ? item.height : item.width,
            context: context ?? "",
            history: options?.history ?? [],
            focused: options?.focused ?? false
        };
        if (options?.transient) {
            const t = options.transient;
            PanelRouter.peek(id, screen.name, origin, t.owner, t.closeDelay, t.closeOnLeave);
        } else if (options?.open) {
            PanelRouter.open(id, screen.name, origin);
        } else {
            PanelRouter.toggle(id, screen.name, origin);
        }
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
            // no shadow while a panel is joined: it would fall beside the joint, outside the one surface
            raised: win.shadow && win.joinProgress === 0
            fill: Theme.alpha(Theme.glass, win.sheetOpacity)
            // a joined panel and the bar are one surface: no highlight line along the seam
            sheen: Material.sheenAlpha > 0 && win.joinProgress === 0
            // the outline gives way while a panel is joined (it ran along the joint as a light seam); the joined
            // panel draws none either, so the two read as one surface
            edge: win.border && win.joinProgress === 0
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

            // ── the signal mark: where the open panel came from. One per bar, on its inner edge (the side the panel
            // grows from), under the widget that opened it; it glides when the panel passes to another widget here
            Item {
                id: mark
                readonly property var entry: win.openEntry
                readonly property bool mine: entry !== null && (entry.barId ?? "") === (win.spec.id ?? "") && (entry.itemSpan ?? 0) > 0
                // the opener's centre along the bar, in the pill's coordinates
                readonly property real centre: !entry ? 0 : win.vertical ? entry.originY - win.windowScreenY() - pill.y : entry.originX - win.windowScreenX() - pill.x
                readonly property real span: Math.max(10, Math.round((entry?.itemSpan ?? 0) * 0.55))
                property real at: centre
                property real length: span
                onCentreChanged: if (mine)
                    at = centre
                onSpanChanged: if (mine)
                    length = span
                onMineChanged: if (mine) {
                    // a fresh opening places the mark at once; only a hand-over within the bar glides
                    if (opacity < 0.05) {
                        atMove.enabled = false;
                        at = centre;
                        length = span;
                        atMove.enabled = true;
                    }
                }
                Behavior on at {
                    id: atMove
                    Anim {
                        role: "spatial"
                    }
                }
                Behavior on length {
                    Anim {
                        role: "spatial"
                    }
                }
                opacity: mine ? 1 : 0
                Behavior on opacity {
                    Anim {
                        role: "effects"
                    }
                }
                visible: opacity > 0.01
                // on the inner edge: the bottom of a top bar, the right of a left bar …
                readonly property real thick: 2
                x: win.vertical ? (win.edge === "left" ? pill.width - thick - 1 : 1) : at - length / 2
                y: win.vertical ? at - length / 2 : (win.edge === "top" ? pill.height - thick - 1 : 1)
                width: win.vertical ? thick : length
                height: win.vertical ? length : thick
                z: 2
                // light, not paint: a soft glow toward the bar's middle, the line itself in the accent
                Rectangle {
                    readonly property real reach: 7
                    x: win.vertical ? (win.edge === "left" ? -reach : 0) : -reach
                    y: win.vertical ? -reach : (win.edge === "top" ? -reach : 0)
                    width: win.vertical ? reach + mark.thick : parent.width + reach * 2
                    height: win.vertical ? parent.height + reach * 2 : reach + mark.thick
                    radius: reach
                    gradient: Gradient {
                        orientation: win.vertical ? Gradient.Horizontal : Gradient.Vertical
                        GradientStop {
                            position: 0
                            color: win.edge === "top" || win.edge === "left" ? "transparent" : Theme.signalGlow
                        }
                        GradientStop {
                            position: 1
                            color: win.edge === "top" || win.edge === "left" ? Theme.signalGlow : "transparent"
                        }
                    }
                }
                Rectangle {
                    anchors.fill: parent
                    radius: mark.thick / 2
                    color: Theme.accent
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
