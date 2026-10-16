import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Components
import qs.Services
import "../../Common/Droplet.js" as Droplet

// A focused panel: placed beside the widget that opened it, grows out of the bar edge, leaves faster
// than it arrived. The content is chosen by panel id.
PanelWindow {
    id: win

    required property var entry
    property bool closing: false
    signal dismissed

    // the last open entry: a warm, hidden surface keeps its content instead of unloading it
    property var held: entry
    onEntryChanged: if (entry)
        held = entry

    // placed at a spot of the work area ([control_panel] position), or "" beside what opened it
    readonly property string place: bare ? "" : held?.place ?? ""
    readonly property var work: PanelRouter.workArea(screen?.name ?? "", sw, sh)
    readonly property int placeMargin: Math.max(0, Math.min(64, Config.controlPanel?.position_margin ?? 12))
    // a placed panel still grows from its nearest side (a centred one from its middle)
    readonly property string edge: place === "" ? held?.edge ?? "top" : place.startsWith("top") ? "top" : place.startsWith("bottom") ? "bottom" : place === "middle-left" ? "left" : place === "middle-right" ? "right" : "center"
    // a bare panel (the wallpaper carousel) covers the screen and draws its own surfaces over a dimmed desktop
    readonly property bool bare: content.bare
    // never wider than the room it has (the work area when placed, else the screen)
    readonly property int panelWidth: bare ? sw : Math.min(content.preferredWidth > 0 ? content.preferredWidth : Config.panels.width, place !== "" ? work.w - 2 * placeMargin : sw - 2 * screenMargin)
    // never taller than the screen leaves room for: past that, the content scrolls inside the card
    readonly property real maxCardHeight: place !== "" ? work.h - 2 * placeMargin : edge === "top" || edge === "bottom" ? sh - 2 * (extent + gap) : sh - 2 * screenMargin
    // whole pixels: a panel joined to a bottom (or right) bar meets it at its far edge, where a fractional height
    // left a half-covered row — a light line along the joint
    readonly property real cardHeight: bare ? sh : Math.round(Math.min(content.implicitHeight, maxCardHeight))
    // ── the morph: a panel that changes (another icon's panel, a tab, content that grows) glides there ──
    // [panels] switch: morph (the card moves and resizes, contents cross-fade) | fade | none;
    // morph_curve: liquid (a slight overshoot) | emphasized | smooth | style (the animation style's);
    // morph_ms: 0 follows the animation speed
    readonly property var pcfg: Config.panels ?? ({})
    readonly property bool morphs: (pcfg.switch ?? "morph") === "morph" && !bare
    readonly property int morphMs: (pcfg.morph_ms ?? 0) > 0 ? Motion.ms(pcfg.morph_ms) : Motion.spatial
    readonly property var morphCurve: ({
            liquid: Motion.curves.expressiveDefaultSpatial,
            emphasized: Motion.curves.emphasized,
            smooth: Motion.curves.emphasizedDecel,
            style: Motion.spatialCurve
        })[pcfg.morph_curve ?? "liquid"] ?? Motion.curves.expressiveDefaultSpatial
    // the card where it is going, and where it is drawn (animated towards it)
    readonly property var target: ({
            x: cardX,
            y: cardY,
            w: panelWidth,
            h: cardHeight
        })
    readonly property bool morphReady: morphs && revealed > 0.99 && !closing
    property real ax: cardX
    property real ay: cardY
    property real aw: panelWidth
    property real ah: cardHeight
    Behavior on ax {
        enabled: win.morphReady
        NumberAnimation {
            duration: win.morphMs
            easing.type: Easing.BezierSpline
            easing.bezierCurve: win.morphCurve
        }
    }
    Behavior on ay {
        enabled: win.morphReady
        NumberAnimation {
            duration: win.morphMs
            easing.type: Easing.BezierSpline
            easing.bezierCurve: win.morphCurve
        }
    }
    Behavior on aw {
        enabled: win.morphReady
        NumberAnimation {
            duration: win.morphMs
            easing.type: Easing.BezierSpline
            easing.bezierCurve: win.morphCurve
        }
    }
    Behavior on ah {
        enabled: win.morphReady || (win.revealed > 0.99 && !win.closing)
        NumberAnimation {
            duration: win.morphReady ? win.morphMs : Motion.morph
            easing.type: Easing.BezierSpline
            easing.bezierCurve: win.morphReady ? win.morphCurve : Motion.enterCurve
        }
    }
    // The window spans where the card was and where it is going while it glides, so the surface is
    // resized once per change, never every frame; it settles on the target afterwards. (The overshoot of
    // the liquid curve stays inside the shadow pad.)
    property var span: ({
            x: cardX,
            y: cardY,
            w: panelWidth,
            h: cardHeight
        })
    function unite(a: var, b: var): var {
        const x = Math.min(a.x, b.x), y = Math.min(a.y, b.y);
        return {
            x: x,
            y: y,
            w: Math.max(a.x + a.w, b.x + b.w) - x,
            h: Math.max(a.y + a.h, b.y + b.h) - y
        };
    }
    onTargetChanged: {
        // only a panel already on screen glides; one appearing (or a bare one) takes its size at once — a
        // window resized twice while it was being shown kept the stale size (the wallpaper browser at 432 px)
        if (!morphReady) {
            settle.stop();
            span = target;
            return;
        }
        const now = { x: ax, y: ay, w: aw, h: ah };
        span = unite(settle.running ? unite(span, now) : now, target);
        settle.restart();
    }

    Timer {
        id: settle
        interval: win.morphMs + 60
        onTriggered: win.span = win.target
    }
    readonly property int pad: bare ? 0 : Math.max(Material.shadows && !attached ? Metrics.shadowPad + 6 : 0, attached ? joinRadius + 2 : 0)
    readonly property int gap: attached ? 0 : Metrics.s3

    // ── attached: the panel and the bar it came from are one surface (the native shell's attached panels,
    // Caelestia's drawers). It sits on the bar's inner edge in the bar's own fill, grows out of that edge, and
    // concave fillets join the two where their outlines meet: beside the panel where the bar runs past it (a
    // drawer), beside the bar where the panel runs past it (the bar's corners there go square). Only where they
    // share at least two radii of edge; otherwise it floats beside the bar as before. [panels] attach = false
    // keeps every panel floating.
    readonly property real joinRadius: Metrics.radiusSurface
    readonly property var barSpan: held?.barSpan ?? null
    readonly property bool sideEdge: edge === "top" || edge === "bottom" || edge === "left" || edge === "right"
    readonly property bool horizontalEdge: edge === "top" || edge === "bottom"
    // along the edge, in screen coordinates: where the card runs (its target, not the animated one)
    readonly property real cardStart: horizontalEdge ? cardX : cardY
    readonly property real cardEnd: horizontalEdge ? cardX + panelWidth : cardY + cardHeight
    readonly property bool attached: !bare && place === "" && sideEdge && (pcfg.attach ?? true) && (held?.fillOpacity ?? -1) >= 0 && barSpan !== null && Math.min(barSpan[1], cardEnd) - Math.max(barSpan[0], cardStart) >= 2 * joinRadius
    // each end of the joint: drawer (the bar runs past the panel) · t (the panel runs past the bar) · flush
    readonly property string startJoin: !attached ? "" : barSpan[0] <= cardStart - joinRadius / 2 ? "drawer" : cardStart <= barSpan[0] - joinRadius / 2 ? "t" : "flush"
    readonly property string endJoin: !attached ? "" : barSpan[1] >= cardEnd + joinRadius / 2 ? "drawer" : cardEnd >= barSpan[1] + joinRadius / 2 ? "t" : "flush"
    // how far the panel has grown out of the bar, and the fillets' radius: they arrive as the growth lands
    readonly property real grow: attached && !droplet ? revealed : 1
    // the fillets arrive over the second half of the growth, once the bar-side edge has cleared the bar
    readonly property real bulgeFrom: 0.5
    readonly property real bulge: attached ? joinRadius * (droplet ? (drop?.join ?? 1) : Math.max(0, Math.min(1, (revealed - bulgeFrom) / (1 - bulgeFrom)))) : 0
    readonly property string joinKey: (held?.barId ?? "") + "@" + (screen?.name ?? "")
    onBulgeChanged: publishJoin()
    onAttachedChanged: publishJoin()
    onJoinKeyChanged: PanelRouter.setJoin(lastJoinKey, null)
    property string lastJoinKey: ""
    function publishJoin(): void {
        if (lastJoinKey !== "" && lastJoinKey !== joinKey)
            PanelRouter.setJoin(lastJoinKey, null);
        lastJoinKey = joinKey;
        if (!attached || bulge <= 0 || (startJoin !== "t" && endJoin !== "t"))
            PanelRouter.setJoin(joinKey, null);
        else
            PanelRouter.setJoin(joinKey, { start: startJoin === "t", end: endJoin === "t", progress: bulge / joinRadius });
    }
    Component.onDestruction: PanelRouter.setJoin(lastJoinKey, null)
    readonly property int screenMargin: Metrics.s3
    readonly property real sw: screen?.width ?? 1920
    readonly property real sh: screen?.height ?? 1080
    readonly property real ox: (held?.originX ?? -1) >= 0 ? held.originX : sw - panelWidth / 2 - screenMargin
    readonly property real oy: (held?.originY ?? -1) >= 0 ? held.originY : 0
    // attached, the panel meets the bar's drawn edge exactly; floating, it keeps the bar's overlap or gap
    readonly property real extent: attached && (held?.reach ?? -1) >= 0 ? held.reach : held?.extent ?? 42

    function clamp(v: real, lo: real, hi: real): real {
        return Math.max(lo, Math.min(hi, v));
    }

    // the card's rectangle on screen
    // "center": not tied to a bar (the launcher); the top stays put while the content grows downwards
    readonly property real placedX: place.endsWith("left") ? work.x + placeMargin : place.endsWith("right") ? work.x + work.w - placeMargin - panelWidth : Math.round(work.x + (work.w - panelWidth) / 2)
    readonly property real placedY: place.startsWith("top") ? work.y + placeMargin : place.startsWith("bottom") ? work.y + work.h - placeMargin - cardHeight : Math.round(work.y + (work.h - cardHeight) / 2)
    // Along its bar the card keeps a margin from the screen's ends — except as far as the bar it opened from
    // reaches: a bar flush with the screen edge takes its panel flush with it too (8 px in, it left a step at
    // the join). Read from the bar's span, not `attached` (which is itself worked out from this position).
    readonly property real alongLo: barSpan ? Math.min(screenMargin, Math.max(0, barSpan[0])) : screenMargin
    readonly property real alongHiGap: barSpan ? Math.min(screenMargin, Math.max(0, (horizontalEdge ? sw : sh) - barSpan[1])) : screenMargin
    readonly property real cardX: bare ? 0 : place !== "" ? placedX : edge === "center" ? Math.round((sw - panelWidth) / 2) : edge === "left" ? extent + gap : edge === "right" ? sw - extent - gap - panelWidth : clamp(ox - panelWidth / 2, alongLo, sw - panelWidth - alongHiGap)
    readonly property real cardY: bare ? 0 : place !== "" ? placedY : edge === "center" ? (content.preferredTop < 0 ? Math.round((sh - cardHeight) / 2) : Math.round(sh * content.preferredTop)) : edge === "top" ? extent + gap : edge === "bottom" ? sh - extent - gap - cardHeight : clamp(oy - cardHeight / 2, alongLo, sh - cardHeight - alongHiGap)
    readonly property var cardRect: ({
            x: Math.round((screen?.x ?? 0) + cardX),
            y: Math.round((screen?.y ?? 0) + cardY),
            w: Math.round(panelWidth),
            h: Math.round(cardHeight),
            // for diagnostics: the window's own position on the output (to composite captures)
            winX: Math.round(winX),
            winY: Math.round(winY),
            attached: attached
        })
    onCardRectChanged: PanelRouter.noteRect(screen?.name ?? "", cardRect)
    readonly property real winX: Math.max(0, span.x - pad)
    readonly property real winY: Math.max(0, span.y - pad)

    WlrLayershell.namespace: "zynith-panel"
    WlrLayershell.layer: WlrLayer.Overlay
    // a closing panel lets go of the keyboard at once, so typing (and a paste) reaches the window beneath
    // a hover-opened panel leaves the keyboard where it is until it is clicked (pinned)
    WlrLayershell.keyboardFocus: win.closing || (win.entry?.transient ?? false) || (win.entry?.preview ?? false) ? WlrKeyboardFocus.None : WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    anchors {
        top: true
        left: true
    }
    margins {
        left: winX
        top: winY
    }
    // +nudge: a window that changed size while it was being shown kept the stale one (the wallpaper browser
    // reopened warm stayed 432 px wide); asking once more a tick later lands the real size
    property int nudge: 0
    implicitWidth: span.x - winX + span.w + pad + nudge
    implicitHeight: span.y - winY + span.h + pad
    function reassert(): void {
        nudge = 1;
        unnudge.restart();
    }
    Timer {
        id: unnudge
        interval: 60
        onTriggered: win.nudge = 0
    }
    // after the surface is mapped again, once more (the first configure can swallow a size change)
    Timer {
        id: settleSize
        interval: 120
        onTriggered: if (Math.abs(win.width - win.implicitWidth) > 1 || Math.abs(win.height - win.implicitHeight) > 1)
            win.reassert()
    }
    onWidthChanged: {
        PanelRouter.windowSizes[screen?.name ?? ""] = [Math.round(width), Math.round(height)];
        if (visible && Math.abs(width - implicitWidth) > 1)
            settleSize.restart();
    }
    onHeightChanged: PanelRouter.windowSizes[screen?.name ?? ""] = [Math.round(width), Math.round(height)]

    // input follows what is drawn: while the drop forms, only its bounds take the pointer
    mask: Region {
        item: win.dropping ? dropBounds : card
    }

    // the pointer on the card holds a hover-opened panel; a press in it pins it
    HoverHandler {
        id: cardHover
        enabled: !win.closing
        onHoveredChanged: PanelRouter.hold(win.screen?.name ?? "", "panel", hovered)
    }
    TapHandler {
        gesturePolicy: TapHandler.DragThreshold
        grabPermissions: PointerHandler.TakeOverForbidden
        onPressedChanged: if (pressed)
            PanelRouter.pin(win.screen?.name ?? "")
    }
    BlurRegion {
        window: win
        // while the drop forms, the blur follows its head (round, with the head's radius); the thin neck goes
        // without for those few frames rather than a rectangle being blurred beside it
        item: win.bare ? content.blurItem : win.dropping ? dropHead : card
        // the card's corners exactly as drawn (attached: square only where it meets the bar)
        radius: win.dropping ? (win.blurHead?.r ?? 0) : card.radius
        corners: win.dropping ? (win.blurHead?.corners ?? null) : card.drawnCorners
        // the blur only once the card is drawn over it: an attached card fades in within the first sixth of its
        // growth, and a region switched on before that showed the bare backdrop (in Glass, the wallpaper) as a
        // rectangle over the windows for a frame
        followOpacity: !win.bare
        // an attached panel's fillets, each its square less the quarter circle that cuts it
        extra: win.attached && !win.dropping ? fillets.blurShapes : []
    }

    // dims the desktop behind a bare panel; never blurs it, so an applied wallpaper shows through. The
    // panel may tint it (the wallpaper carousel takes the focused wallpaper's colour) and lift it for a moment.
    Rectangle {
        anchors.fill: parent
        visible: win.bare
        color: Theme.alpha(content.backdropTint !== undefined ? Theme.mix(Theme.base, content.backdropTint, 0.28) : Theme.base, 0.58 * (content.backdropDim ?? 1))
        opacity: Motion.ease("standardDecel", win.revealed)
        Behavior on color {
            ColorAnim {
                role: "spatialSlow"
            }
        }
    }

    // 0 = gone, 1 = in place
    property real revealed: 0

    // ── the water drop (Common/Droplet.js): the panel gathers on the edge it opens from, draws in to a drop that
    // hangs from a thinning neck, and swells into itself; closing runs it back, and an interrupted one reverses
    // from where it is (the silhouette is a function of `revealed` alone). The card is drawn at its final size the
    // whole time and only masked to the silhouette, so its fill, blur and page are revealed by the drop, never
    // redrawn or swapped. [panels] entrance = drop (default) | grow (the earlier growth and fade). A centred or
    // full-screen surface keeps its own entrance.
    readonly property bool droplet: !bare && sideEdge && (pcfg.entrance ?? "drop") === "drop" && Motion.reveal > 0
    readonly property bool dropping: droplet && visible && revealed < 0.999
    readonly property var drop: droplet ? Droplet.shape(revealed, {
            edge: edge,
            attached: attached,
            ox: horizontalEdge ? ox - cardX : oy - cardY,
            along: horizontalEdge ? panelWidth : cardHeight,
            depth: horizontalEdge ? cardHeight : panelWidth,
            corners: card.drawnCorners,
            radius: card.radius,
            pathHead: false
        }) : null
    // The blur's region reaches the compositor a frame before the picture it belongs to: while the drop swells, a
    // region of the current head showed as a pale rim round the head still on screen. It takes the overlap of this
    // frame's head and the last one's, so it is never larger than what is drawn (shrinking, the overlap is the new one).
    property var lastHead: null
    property var blurHead: null
    onDropChanged: {
        const h = drop?.head ?? null;
        const p = lastHead;
        lastHead = h;
        if (!h || !p) {
            blurHead = h;
            return;
        }
        const x0 = Math.max(h.x, p.x), y0 = Math.max(h.y, p.y);
        const x1 = Math.min(h.x + h.w, p.x + p.w), y1 = Math.min(h.y + h.h, p.y + p.h);
        blurHead = {
            x: x0,
            y: y0,
            w: Math.max(0, x1 - x0),
            h: Math.max(0, y1 - y0),
            r: Math.min(h.r, p.r),
            corners: h.corners.map((c, i) => Math.min(c, p.corners[i]))
        };
    }

    // a bare panel choreographs its own pieces from `revealed`, so it gets the progress linear and longer
    NumberAnimation {
        id: enter
        target: win
        property: "revealed"
        to: 1
        duration: win.bare ? Motion.scene + 160 : win.droplet ? Motion.ms(560) : Motion.reveal
        // the drop eases each of its phases itself, so it takes the progress linear
        easing.type: win.bare || win.droplet ? Easing.Linear : Motion.enterEasing
        onFinished: win.entering = false
    }
    NumberAnimation {
        id: leave
        target: win
        property: "revealed"
        to: 0
        duration: win.bare ? Motion.spatialFast : win.droplet ? Motion.ms(320) : Motion.dismiss
        easing.type: win.bare || win.droplet ? Easing.Linear : Motion.exitEasing
        onFinished: win.dismissed()
    }
    // content can turn out bare only once it has loaded: the entrance restarts on the bare timing from
    // where it is, so the choreography still gets its full length
    onBareChanged: {
        span = target;
        settleSize.restart();
        if (bare && enter.running)
            restartEnter();
    }
    function restartEnter(): void {
        enter.stop();
        enter.start();
    }

    // the entrance plays once per showing, whether the window is new or warm
    property bool entering: false
    // counts appearances, so content can start fresh each time (warm or not)
    property int showings: 0
    function begin(): void {
        if (entering)
            return;
        entering = true;
        showings++;
        leave.stop();
        revealed = 0;
        enter.restart();
    }
    Component.onCompleted: if (visible)
        begin()
    onVisibleChanged: {
        if (visible) {
            settle.stop();
            span = target;
            begin();
            settleSize.restart();
        } else {
            entering = false;
        }
    }

    // frame pacing while the surface animates (Diagnostics; costs nothing when idle)
    property var frameDeltas: []
    FrameAnimation {
        running: enter.running || leave.running
        onTriggered: win.frameDeltas.push(frameTime * 1000)
        onRunningChanged: {
            if (!running && win.frameDeltas.length > 1) {
                Diagnostics.record(win.closing ? "panel-close" : "panel-open", win.frameDeltas.slice(1));
                win.frameDeltas = [];
            }
        }
    }
    onClosingChanged: {
        if (closing) {
            PanelRouter.hold(screen?.name ?? "", "panel", false);
            enter.stop();
            leave.start();
        } else {
            leave.stop();
            enter.start();
        }
    }

    // the card and its fillets in one item: what the window draws (and, for diagnostics, what a capture of
    // the whole panel takes: zynith-ui ipc captureBar panelwin@<screen> <png>)
    Item {
        id: surfaceScene
        anchors.fill: parent
        Component.onCompleted: PanelRouter.barItems["panelwin@" + (win.screen?.name ?? "")] = surfaceScene

        Glass {
            id: card
            // for diagnostics: the panel's own pixels (zynith-ui ipc captureBar panel@<screen> <png>)
            Component.onCompleted: PanelRouter.barItems["panel@" + (win.screen?.name ?? "")] = card

            // attached, the card grows out of the bar's edge (its far side moves; the joint stays put)
            x: win.ax - win.winX + (win.attached && win.edge === "right" ? win.aw * (1 - win.grow) : 0)
            y: win.ay - win.winY + (win.attached && win.edge === "bottom" ? win.ah * (1 - win.grow) : 0)
            width: win.aw * (win.attached && !win.horizontalEdge ? win.grow : 1)
            height: win.ah * (win.attached && win.horizontalEdge ? win.grow : 1)
            radius: Metrics.radiusSurface
            // the bar-side corners: square where the bar continues past them, rounded where the panel runs past
            // the bar (a fillet then joins the bar's side instead)
            corners: !win.attached ? null : ({
                    top: [win.startJoin === "t" ? radius : 0, win.endJoin === "t" ? radius : 0, radius, radius],
                    bottom: [radius, radius, win.endJoin === "t" ? radius : 0, win.startJoin === "t" ? radius : 0],
                    left: [win.startJoin === "t" ? radius : 0, radius, radius, win.endJoin === "t" ? radius : 0],
                    right: [radius, win.startJoin === "t" ? radius : 0, win.endJoin === "t" ? radius : 0, radius]
                })[win.edge]
            raised: !win.bare && !win.attached
            // attached, the bar's own fill, so the seam disappears
            // attached: the bar's own fill, so the seam disappears — resolved live by the bar's rule (Solid is opaque;
            // else the bar's own opacity, else the material's), not the number taken when the panel opened
            fill: win.bare ? "transparent" : win.attached ? Theme.alpha(Theme.glass, !Material.solid && (win.held.barOpacity ?? 0) > 0 ? Math.min(1, win.held.barOpacity) : Theme.glassAlpha) : Theme.glass
            edge: !win.bare && !win.attached
            sheen: !win.bare && !win.attached && Material.sheenAlpha > 0

            opacity: win.bare || win.droplet ? 1 : win.attached ? Math.min(1, win.revealed * 6) : win.revealed

            // the drop: masked to its silhouette while it forms (no layer at rest)
            layer.enabled: win.dropping
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: dropMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1
            }
            // a floating panel's shadow settles in once the drop has become the card
            shadowOpacity: win.dropping ? 0 : 1
            Behavior on shadowOpacity {
                enabled: !win.dropping
                NumberAnimation {
                    duration: Motion.effects
                }
            }

            // floating: grow from the bar side, a few pixels of travel; attached: the geometry does it
            readonly property real travel: win.bare || win.attached || win.droplet ? 0 : (1 - win.revealed) * Motion.revealOffset
            transform: [
                Scale {
                    origin.x: win.edge === "center" ? card.width / 2 : win.edge === "left" ? 0 : win.edge === "right" ? card.width : win.place !== "" ? (win.place.endsWith("left") ? 0 : win.place.endsWith("right") ? card.width : card.width / 2) : win.ox - win.cardX
                    origin.y: win.edge === "center" ? (win.place === "center" ? card.height / 2 : 0) : win.edge === "top" ? 0 : win.edge === "bottom" ? card.height : win.place !== "" ? card.height / 2 : win.oy - win.cardY
                    xScale: win.bare || win.attached || win.droplet ? 1 : Motion.revealScale + (1 - Motion.revealScale) * win.revealed
                    yScale: win.bare || win.attached || win.droplet ? 1 : Motion.revealScale + (1 - Motion.revealScale) * win.revealed
                },
                Translate {
                    x: win.edge === "left" ? -card.travel : win.edge === "right" ? card.travel : 0
                    y: win.edge === "top" ? -card.travel : win.edge === "bottom" ? card.travel : 0
                }
            ]

            Item {
                anchors.fill: parent
                focus: true
                Keys.onEscapePressed: PanelRouter.close(win.screen.name)
                Keys.onBackPressed: PanelRouter.back(win.screen.name)
                // the tabs from the keyboard: Ctrl+Tab / Ctrl+Shift+Tab or Ctrl+PgDn / Ctrl+PgUp step, Alt+1… jumps
                Keys.onPressed: event => {
                    const ctrl = event.modifiers & Qt.ControlModifier;
                    // Shift+Tab arrives as Backtab, or as Tab with Shift held (verified with real keys: the latter)
                    const back = event.key === Qt.Key_Backtab || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier));
                    if (ctrl && (back || event.key === Qt.Key_PageUp))
                        event.accepted = content.stepTab(-1);
                    else if (ctrl && (event.key === Qt.Key_Tab || event.key === Qt.Key_PageDown))
                        event.accepted = content.stepTab(1);
                    else if ((event.modifiers & Qt.AltModifier) && event.key >= Qt.Key_1 && event.key <= Qt.Key_9)
                        event.accepted = content.goTab(event.key - Qt.Key_1);
                }
            }

            // clips content while the card height animates; the shadow stays outside. Content taller than the
            // card scrolls (only then: a panel that fits keeps its own wheel and drag).
            Flickable {
                id: scroller
                anchors.fill: parent
                clip: true
                contentWidth: width
                contentHeight: content.implicitHeight
                interactive: !win.bare && content.implicitHeight > height + 1
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.VerticalFlick
                // a new panel starts at its top
                Connections {
                    target: content
                    function onShownIdChanged(): void {
                        scroller.contentY = 0;
                    }
                }

                PanelContent {
                    id: content
                    // attached: the page slides out from behind the bar with the growing edge
                    transform: Translate {
                        x: win.attached && win.edge === "left" ? -win.aw * (1 - win.grow) : 0
                        y: win.attached && win.edge === "top" ? -win.ah * (1 - win.grow) : 0
                    }

                    // laid out at the size it is going to, centred in the card while the card glides there (the
                    // card clips it), so nothing reflows every frame
                    width: win.panelWidth
                    x: Math.round((scroller.width - width) / 2)
                    panelId: win.held?.id ?? ""
                    peek: win.held?.transient ?? false
                    focused: win.held?.focused ?? false
                    history: win.held?.history ?? []
                    context: win.held?.context ?? ""
                    showings: win.showings
                    screen: win.screen
                    // in a drop, the page arrives with the swell (its own staggers run on that)
                    opacity: win.droplet ? (win.drop?.content ?? 1) : 1
                    visibleProgress: win.droplet ? (win.drop?.content ?? 1) : win.revealed
                    active: win.visible
                    // the card's own top corners (attached: square where it meets the bar), for the hero's picture
                    topCorners: card.corners ? [card.corners[0], card.corners[1]] : [card.radius, card.radius]
                }
            }
            // where in a scrolled panel you are
            Rectangle {
                visible: scroller.interactive
                anchors.right: parent.right
                anchors.rightMargin: 3
                y: scroller.visibleArea.yPosition * scroller.height + 6
                width: 3
                height: Math.max(24, scroller.visibleArea.heightRatio * scroller.height - 12)
                radius: 2
                color: Theme.alpha(Theme.ink, scroller.moving ? 0.35 : 0.14)
                Behavior on color {
                    ColorAnim {}
                }
            }
        }

        // ── the drop's silhouette (the card's mask), its head (the blur's shape) and bounds (the input region) ──
        Item {
            id: dropMask
            x: card.x
            y: card.y
            width: card.width
            height: card.height
            visible: false
            layer.enabled: win.dropping
            // The head is a plain rounded rectangle, drawn in the frame its geometry changes: as part of the path (a
            // Shape) it reached the screen later still, and the blur showed past it as a pale band ~10 px wide while
            // it swelled. The neck and the menisci (no blur under them) stay a path.
            Rectangle {
                x: win.drop?.head.x ?? 0
                y: win.drop?.head.y ?? 0
                width: win.drop?.head.w ?? 0
                height: win.drop?.head.h ?? 0
                readonly property var c: win.drop?.head.corners ?? [0, 0, 0, 0]
                topLeftRadius: c[0]
                topRightRadius: c[1]
                bottomRightRadius: c[2]
                bottomLeftRadius: c[3]
                color: "white"
                antialiasing: true
            }
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    fillColor: "white"
                    strokeColor: "transparent"
                    strokeWidth: 0
                    fillRule: ShapePath.WindingFill
                    PathSvg {
                        path: win.dropping ? (win.drop?.path ?? "") : ""
                    }
                }
            }
        }
        Item {
            id: dropHead
            visible: win.dropping
            x: card.x + (win.blurHead?.x ?? 0)
            y: card.y + (win.blurHead?.y ?? 0)
            width: win.blurHead?.w ?? 0
            height: win.blurHead?.h ?? 0
        }
        Item {
            id: dropBounds
            x: card.x + (win.drop?.bounds.x ?? 0)
            y: card.y + (win.drop?.bounds.y ?? 0)
            width: win.drop?.bounds.w ?? card.width
            height: win.drop?.bounds.h ?? card.height
        }

        // ── the fillets joining an attached panel to its bar ──
        Item {
            id: fillets
            anchors.fill: parent
            visible: win.attached && win.bulge > 0.5
            // in window coordinates: the joint line and the card's ends along it, the bar's ends along it
            readonly property real r: win.bulge
            readonly property real cx: card.x
            readonly property real cy: card.y
            readonly property real cw: card.width
            readonly property real ch: card.height
            readonly property real b0: win.attached ? win.barSpan[0] - (win.horizontalEdge ? win.winX : win.winY) : 0
            readonly property real b1: win.attached ? win.barSpan[1] - (win.horizontalEdge ? win.winX : win.winY) : 0
            // each: { x, y, solid } — the r×r square and the corner of it that is filled
            readonly property var shapes: {
                if (!win.attached)
                    return [];
                const r = fillets.r, out = [];
                const add = (mode, a, b) => {
                    if (mode === "drawer")
                        out.push(a);
                    else if (mode === "t")
                        out.push(b);
                };
                const e = win.edge;
                if (e === "top") {
                    add(win.startJoin, { x: cx - r, y: cy, solid: "tr" }, { x: b0 - r, y: cy - r, solid: "br" });
                    add(win.endJoin, { x: cx + cw, y: cy, solid: "tl" }, { x: b1, y: cy - r, solid: "bl" });
                } else if (e === "bottom") {
                    const j = cy + ch;
                    add(win.startJoin, { x: cx - r, y: j - r, solid: "br" }, { x: b0 - r, y: j, solid: "tr" });
                    add(win.endJoin, { x: cx + cw, y: j - r, solid: "bl" }, { x: b1, y: j, solid: "tl" });
                } else if (e === "left") {
                    add(win.startJoin, { x: cx, y: cy - r, solid: "bl" }, { x: cx - r, y: b0 - r, solid: "br" });
                    add(win.endJoin, { x: cx, y: cy + ch, solid: "tl" }, { x: cx - r, y: b1, solid: "tr" });
                } else {
                    const j = cx + cw;
                    add(win.startJoin, { x: j - r, y: cy - r, solid: "br" }, { x: j, y: b0 - r, solid: "bl" });
                    add(win.endJoin, { x: j - r, y: cy + ch, solid: "tr" }, { x: j, y: b1, solid: "tl" });
                }
                return out;
            }
            // for the compositor's blur: each square, less the circle centred on its open corner
            readonly property var blurShapes: shapes.map(f => {
                const ox = f.solid === "tr" || f.solid === "br" ? f.x : f.x + r;
                const oy = f.solid === "bl" || f.solid === "br" ? f.y : f.y + r;
                return { x: f.x, y: f.y, w: r, h: r, cutX: ox - r, cutY: oy - r, cut: 2 * r };
            })
            Repeater {
                model: fillets.shapes
                delegate: ConcaveCorner {
                    required property var modelData
                    x: modelData.x
                    y: modelData.y
                    r: fillets.r
                    solid: modelData.solid
                    fill: card.fill
                    opacity: card.opacity
                }
            }
        }
    }
}
