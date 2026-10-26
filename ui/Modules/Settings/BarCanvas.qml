import QtQuick
import Quickshell
import qs.Common
import qs.Components
import qs.Services
import Quickshell.Io
import "../../Common/BarModel.js" as BarModel

// The display, with every bar drawn where it sits and in its shape (its corners and concave curves from BarModel,
// the rule the bars themselves draw with). Click a bar to edit it; drag the one you are editing to another edge or
// place along it (it snaps). Placing: every spot a new bar can go is offered; click one.
Item {
    id: canvas

    required property var page
    // offering the spots for a new bar
    property bool placing: false
    signal placed(string edge, string anchor)
    signal cancelled

    readonly property var screen: Quickshell.screens.find(s => s.name === page.screenName) ?? Quickshell.screens[0] ?? null
    readonly property real sw: screen?.width ?? 1920
    readonly property real sh: screen?.height ?? 1080
    readonly property real k: Math.min((width - 2) / sw, (height - 2) / sh)
    readonly property var reserved: BarModel.reservations(page.bars, screen?.name ?? "")
    readonly property real ox: (width - sw * k) / 2
    readonly property real oy: (height - sh * k) / 2

    // where the running shell has each bar ("id@output" → [x, y, w, h]): asked when the page opens and after each
    // change (the shell lays bars out from what they hold, which only it knows); never polled
    property var live: ({})
    Process {
        id: ask
        command: [Paths.uiScript, "ipc", "bars"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    const out = {};
                    for (const k in d)
                        out[k] = d[k].bar;
                    canvas.live = out;
                } catch (e) {}
            }
        }
    }
    Timer {
        id: askSoon
        interval: 350
        onTriggered: ask.running = true
    }
    Component.onCompleted: ask.running = true
    Connections {
        target: BarEdits
        function onRevisionChanged(): void {
            askSoon.restart();
        }
    }
    // where a bar sits: as the shell drew it, else as its settings say (its length the stretch, its own, or an
    // estimate from what it holds)
    function rect(b: var): var {
        const real = live[(b.id ?? "") + "@" + (screen?.name ?? "")];
        if (real && b.enabled !== false && !placing)
            return { x: real[0], y: real[1], w: real[2], h: real[3] };
        const vert = b.edge === "left" || b.edge === "right";
        const L = vert ? sh : sw;
        const range = BarModel.alongRange(b, L, reserved);
        const t = b.thickness ?? 34;
        const m = b.margin ?? 0;
        const off = b.anchor === "center" ? 0 : (b.offset ?? 0);
        const count = BarModel.entriesOf(b).length;
        const len = b.anchor === "fill" ? (range[1] - range[0]) - off * 2 : (b.length ?? 0) > 0 ? b.length : Math.max(t * 2, count * t * 0.95 + (b.padding ?? 12) * 2);
        const along = b.anchor === "fill" || b.anchor === "start" ? range[0] + off : b.anchor === "end" ? range[1] - off - len : range[0] + (range[1] - range[0] - len) / 2;
        const across = b.edge === "top" || b.edge === "left" ? m : (vert ? sw : sh) - m - t;
        return vert ? { x: across, y: along, w: t, h: len } : { x: along, y: across, w: len, h: t };
    }
    // the spots a bar can be put: each edge × start / centre / end / full length
    readonly property var spots: {
        const out = [];
        for (const e of BarModel.edges)
            for (const a of BarModel.anchors)
                out.push({ edge: e, anchor: a, r: rect({ edge: e, anchor: a, thickness: 34, margin: 6, offset: a === "fill" ? 0 : 8, length: a === "fill" ? 0 : ((e === "left" || e === "right") ? sh : sw) * 0.22, widgets: {} }) });
        return out;
    }
    // the spot nearest a point (screen px): its edge is the nearest screen side, its place the third of the edge it is in
    function snap(x: real, y: real, keepFill: bool): var {
        const d = { left: x, right: sw - x, top: y, bottom: sh - y };
        const edge = Object.keys(d).reduce((a, b) => d[a] <= d[b] ? a : b);
        const vert = edge === "left" || edge === "right";
        const f = vert ? y / sh : x / sw;
        const anchor = keepFill ? "fill" : f < 1 / 3 ? "start" : f > 2 / 3 ? "end" : "center";
        return { edge: edge, anchor: anchor };
    }

    // the screen
    Rectangle {
        id: monitor
        x: canvas.ox
        y: canvas.oy
        width: canvas.sw * canvas.k
        height: canvas.sh * canvas.k
        radius: Metrics.radiusMd
        color: Theme.surfaceLow
        border.width: 1
        border.color: Theme.rule
        clip: true
        Label {
            anchors.centerIn: parent
            role: "micro"
            caps: true
            tone: "faint"
            text: canvas.placing ? "Click where the new bar should go" : (canvas.screen?.name ?? "screen") + " · " + canvas.sw + " × " + canvas.sh
        }

        // ── the bars ──
        Repeater {
            model: canvas.placing ? [] : canvas.page.bars.filter(b => BarModel.onScreen(b, canvas.screen?.name ?? ""))
            delegate: Item {
                id: barShape
                required property var modelData
                readonly property bool selected: modelData.id === canvas.page.barId
                readonly property bool on: modelData.enabled !== false
                readonly property var r: canvas.rect(modelData)
                readonly property real kk: canvas.k
                readonly property var touch: BarModel.endsTouch(modelData)
                readonly property var radii: BarModel.cornerRadii(modelData, { w: r.w, h: r.h }, Metrics.radiusScale, null, touch).map(v => v * kk)
                x: r.x * kk
                y: r.y * kk
                width: Math.max(3, r.w * kk)
                height: Math.max(3, r.h * kk)
                z: selected ? 2 : 1
                opacity: dragArea.drag.active ? 0.35 : 1
                Rectangle {
                    anchors.fill: parent
                    color: !barShape.on ? "transparent" : barShape.selected ? Theme.accent : Theme.inkMuted
                    border.width: barShape.on ? 0 : 1
                    border.color: barShape.selected ? Theme.accent : Theme.inkFaint
                    topLeftRadius: barShape.radii[0]
                    topRightRadius: barShape.radii[1]
                    bottomRightRadius: barShape.radii[2]
                    bottomLeftRadius: barShape.radii[3]
                }
                // its concave curves, against the screen edges
                Repeater {
                    model: barShape.on ? BarModel.fillets(barShape.modelData, { x: 0, y: 0, w: barShape.r.w, h: barShape.r.h }, { start: 999, end: 999, inner: 999, outer: 999 }, barShape.touch, Metrics.radiusScale) : []
                    delegate: ConcaveCorner {
                        required property var modelData
                        x: modelData.x * barShape.kk
                        y: modelData.y * barShape.kk
                        r: Math.max(1, modelData.r * barShape.kk)
                        solid: modelData.solid
                        fill: barShape.selected ? Theme.accent : Theme.inkMuted
                    }
                }
                MouseArea {
                    id: dragArea
                    anchors.fill: parent
                    anchors.margins: -5
                    cursorShape: barShape.selected ? (drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor) : Qt.PointingHandCursor
                    drag.target: barShape.selected ? ghost : null
                    drag.threshold: 6
                    onPressed: mouse => {
                        if (!barShape.selected) {
                            canvas.page.select(barShape.modelData.id);
                            return;
                        }
                        ghost.width = barShape.width;
                        ghost.height = barShape.height;
                        ghost.x = barShape.x;
                        ghost.y = barShape.y;
                    }
                    onPositionChanged: mouse => {
                        if (!drag.active)
                            return;
                        const p = mapToItem(monitor, mouse.x, mouse.y);
                        ghost.target = canvas.snap(p.x / canvas.k, p.y / canvas.k, barShape.modelData.anchor === "fill");
                    }
                    onReleased: {
                        if (ghost.target && (ghost.target.edge !== barShape.modelData.edge || ghost.target.anchor !== barShape.modelData.anchor))
                            BarEdits.place(barShape.modelData.id, ghost.target.edge, ghost.target.anchor);
                        ghost.target = null;
                    }
                }
            }
        }

        // where a dragged bar will land
        Rectangle {
            readonly property var r: ghost.target ? canvas.rect(Object.assign({}, canvas.page.bar ?? {}, ghost.target, { offset: 0 })) : null
            visible: r !== null
            x: (r?.x ?? 0) * canvas.k
            y: (r?.y ?? 0) * canvas.k
            width: Math.max(3, (r?.w ?? 0) * canvas.k)
            height: Math.max(3, (r?.h ?? 0) * canvas.k)
            radius: Math.min(width, height) / 2
            color: Theme.accentSoft
            border.width: 1
            border.color: Theme.accent
        }
        // what the pointer drags (invisible: the target above shows where it goes)
        Item {
            id: ghost
            property var target: null
        }

        // ── placing a new bar: every spot ──
        Repeater {
            model: canvas.placing ? canvas.spots : []
            delegate: Rectangle {
                id: spot
                required property var modelData
                readonly property var r: modelData.r
                objectName: "spot-" + modelData.edge + "-" + modelData.anchor
                x: r.x * canvas.k
                y: r.y * canvas.k
                width: Math.max(4, r.w * canvas.k)
                height: Math.max(4, r.h * canvas.k)
                radius: Math.min(width, height) / 2
                z: modelData.anchor === "fill" ? 0 : 1
                color: spotArea.containsMouse ? Theme.accent : Theme.alpha(Theme.accent, modelData.anchor === "fill" ? 0.12 : 0.28)
                border.width: 1
                border.color: Theme.alpha(Theme.accent, 0.6)
                MouseArea {
                    id: spotArea
                    anchors.fill: parent
                    anchors.margins: -3
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: canvas.placed(spot.modelData.edge, spot.modelData.anchor)
                }
                ToolTipLabel {
                    visible: spotArea.containsMouse
                    text: BarModel.positionLabel(spot.modelData)
                }
            }
        }
    }

    // a word beside the pointer, inside the screen
    component ToolTipLabel: Rectangle {
        property alias text: tip.text
        z: 10
        x: Math.min(parent.width + 4, monitor.width - parent.x - width)
        y: -height - 4 < -parent.y ? parent.height + 4 : -height - 4
        width: tip.implicitWidth + Metrics.s3 * 2
        height: tip.implicitHeight + Metrics.s2 * 2
        radius: Metrics.radiusSm
        color: Theme.surfaceHighest
        Label {
            id: tip
            anchors.centerIn: parent
            role: "caption"
        }
    }
}
