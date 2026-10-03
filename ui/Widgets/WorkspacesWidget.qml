import QtQuick
import Quickshell
import Zynith.Native
import qs.Common
import qs.Components
import qs.Services

// The workspaces, drawn from one geometry whatever the style: cells of one size along the bar, a merged
// background behind each run of occupied ones, and a single active indicator that travels between them —
// stretching from the old cell to the new one (trail), gliding (slide), or jumping (none).
// Styles: pills (marks that lengthen for the active one) · numbers · dots · icons (each workspace's apps) ·
// line (only a line marks focus). Every size, colour, label and motion is a setting; the old style names
// (regular, minimal, focus_hint) still work. Left click on a workspace goes there (reserved); the wheel switches.
BarItem {
    id: root

    readonly property var sets: Workspaces.forScreen(screen, opt("show_all_outputs") === true).filter(w => !(opt("hide_when_empty") === true && w.windows === 0 && !w.active))
    readonly property string style: ({
            regular: "pills",
            minimal: "dots",
            focus_hint: "line"
        })[opt("style") ?? "pills"] ?? (opt("style") ?? "pills")
    readonly property bool onFocusedOnly: opt("focused_output_only") === true
    shown: sets.length > 0 && !(onFocusedOnly && Workspaces.focusedOutput !== (screen?.name ?? ""))
    pad: Metrics.s2
    spacing: 0

    // ── sizes ──
    readonly property real cell: Math.max(10, (opt("cell_size") ?? 0) > 0 ? opt("cell_size") : Math.round(root.cross * 0.62))
    readonly property real gap: (opt("spacing") ?? -1) >= 0 ? opt("spacing") : Math.round(cell * 0.18)
    // a mark's thickness (pills, dots), and the active one's length in marks
    // (a pill that carries its number is thick enough to hold it)
    readonly property bool pillLabels: style === "pills" && opt("show_labels") !== false
    readonly property real mark: Math.max(pillLabels ? cell * 0.72 : 3, cell * 0.52 * (opt("pill_scale") ?? 1))
    readonly property real activeLength: opt("active_pill_size") ?? 2.2
    readonly property real inactiveLength: opt("inactive_pill_size") ?? 1
    readonly property real iconSize: (opt("icon_size") ?? 0) > 0 ? opt("icon_size") : Math.round(cell * 0.62)
    readonly property int maxIcons: opt("max_icons") ?? 3
    readonly property bool wantIcons: style === "icons" || (opt("show_icons") === true && style !== "dots" && style !== "pills")

    // ── colours ──
    readonly property color focusTint: Theme.colour(opt("focused_color") ?? "primary")
    readonly property color occupiedTint: Theme.colour(opt("occupied_color") ?? "secondary")
    readonly property color emptyTint: Theme.colour(opt("empty_color") ?? "secondary")
    readonly property color urgentTint: Theme.colour(opt("urgent_color") ?? "error")
    readonly property color labelTint: (opt("label_color") ?? "") !== "" ? Theme.colour(opt("label_color")) : ink
    readonly property real emptyOpacity: opt("empty_opacity") ?? 0.45

    // ── the indicator ──
    readonly property string indicatorShape: {
        const own = opt("indicator") ?? "auto";
        if (own !== "auto")
            return own;
        return style === "line" ? "line" : style === "dots" ? "dot" : style === "pills" ? "mark" : "pill";
    }
    readonly property string motion: Motion.reduced ? "none" : (opt("indicator_motion") ?? "trail")

    // windowList() is a call, so it is asked again whenever workspaces or focus change
    readonly property var windows: {
        NiriState.workspaces;
        NiriState.focusedWindow;
        return wantIcons ? NiriState.windowList() : [];
    }
    function iconsFor(id: var): var {
        return windows.filter(w => w.workspaceId === id).slice(0, maxIcons).map(w => {
            const entry = DesktopEntries.heuristicLookup(w.appId);
            return Quickshell.iconPath(entry?.icon ?? w.appId, true);
        }).filter(s => s !== "");
    }

    function labelOf(w: var): string {
        if (opt("show_labels") === false || style === "dots")
            return "";
        const occupied = w.windows > 0;
        const glyph = w.active ? (opt("active_label") ?? "") : occupied ? (opt("occupied_label") ?? "") : (opt("empty_label") ?? "");
        if (glyph !== "")
            return glyph;
        if (opt("labels_only_when_occupied") === true && !occupied && !w.active)
            return "";
        let raw = opt("label_source") === "name" && w.name !== "" ? w.name : String(w.idx ?? "");
        raw = raw.slice(0, opt("max_label_chars") ?? 2);
        const kase = opt("label_case") ?? "as_is";
        return kase === "upper" ? raw.toUpperCase() : kase === "lower" ? raw.toLowerCase() : raw;
    }

    // each workspace's length along the bar
    function lengthOf(w: var, icons: int): real {
        if (style === "pills")
            return mark * (w.active ? activeLength : inactiveLength);
        if (style === "dots")
            return mark;
        if (wantIcons && icons > 0)
            return Math.max(cell, icons * iconSize + (icons - 1) * 2 + cell * 0.5);
        return cell;
    }
    readonly property var cells: {
        let at = 0;
        const out = [];
        for (const w of sets) {
            const icons = wantIcons ? iconsFor(w.key) : [];
            const len = lengthOf(w, icons.length);
            out.push({
                w: w,
                icons: icons,
                label: labelOf(w),
                from: at,
                len: len
            });
            at += len + gap;
        }
        return out;
    }
    readonly property real total: cells.length > 0 ? cells[cells.length - 1].from + cells[cells.length - 1].len : 0
    readonly property real thick: style === "pills" || style === "dots" ? Math.max(mark, cell * 0.5) : cell
    readonly property int activeIndex: cells.findIndex(c => c.w.active)

    // runs of occupied workspaces, merged
    readonly property var runs: {
        if (opt("occupied_bg") !== true)
            return [];
        const out = [];
        for (const c of cells) {
            const occ = c.w.windows > 0 || c.w.active;
            const last = out[out.length - 1];
            if (occ && last && last.open)
                last.to = c.from + c.len;
            else if (occ)
                out.push({ from: c.from, to: c.from + c.len, open: true });
            if (!occ && last)
                last.open = false;
        }
        return out;
    }

    Item {
        id: track
        implicitWidth: root.vertical ? root.thick : root.total
        implicitHeight: root.vertical ? root.total : root.thick

        // ── merged backgrounds behind occupied runs ──
        Repeater {
            model: root.runs
            delegate: Rectangle {
                required property var modelData
                readonly property real a: modelData.from - 2
                readonly property real b: modelData.to + 2
                x: root.vertical ? -2 : a
                y: root.vertical ? a : -2
                width: root.vertical ? track.width + 4 : b - a
                height: root.vertical ? b - a : track.height + 4
                radius: Math.min(width, height) / 2
                color: Theme.alpha(Theme.colour(root.opt("occupied_bg_color") ?? "surface_variant"), root.opt("occupied_bg_opacity") ?? 0.55)
                Glide on x {}
                Glide on y {}
                Glide on width {}
                Glide on height {}
            }
        }

        // ── the active indicator: head and tail move at different speeds, so it stretches ──
        Item {
            id: indicator
            visible: root.activeIndex >= 0
            readonly property var at: root.activeIndex >= 0 ? root.cells[root.activeIndex] : ({ from: 0, len: root.cell })
            property real head: at.from
            property real tail: at.from
            property real len: at.len
            Behavior on head {
                enabled: root.motion !== "none"
                Anim {
                    role: "spatialFast"
                }
            }
            Behavior on tail {
                enabled: root.motion !== "none"
                Anim {
                    role: root.motion === "trail" ? "spatialSlow" : "spatialFast"
                }
            }
            Behavior on len {
                enabled: root.motion !== "none"
                Anim {
                    role: "spatialFast"
                }
            }
            readonly property real start: Math.min(head, tail)
            readonly property real extent: Math.abs(head - tail) + len

            readonly property string shape: root.indicatorShape
            // across the bar: a pill fills the cell, a mark is a pill's thickness, a dot smaller, a line thin
            readonly property real across: shape === "line" ? Math.max(2, root.cell * 0.12) : shape === "dot" || shape === "mark" ? root.mark : root.thick
            readonly property real crossAt: shape === "line" ? (root.vertical ? (root.bar?.edge === "right" ? 0 : root.thick - across) : (root.bar?.edge === "bottom" ? 0 : root.thick - across)) : (root.thick - across) / 2

            x: root.vertical ? crossAt : start
            y: root.vertical ? start : crossAt
            width: root.vertical ? across : extent
            height: root.vertical ? extent : across

            Rectangle {
                anchors.fill: parent
                radius: indicator.shape === "line" ? indicator.across / 2 : Math.min(width, height) / 2
                color: indicator.shape === "ring" ? "transparent" : root.focusTint
                border.width: indicator.shape === "ring" ? 1.5 : 0
                border.color: root.focusTint
                Behavior on color {
                    ColorAnim {}
                }
            }
        }

        // ── the workspaces ──
        Repeater {
            model: root.cells
            delegate: Item {
                id: cellItem
                required property var modelData
                required property int index
                readonly property var ws: modelData.w
                readonly property bool current: ws.active
                readonly property bool occupied: ws.windows > 0
                readonly property bool hot: area.containsMouse && root.opt("change_color_on_hover") !== false
                // on a filled indicator the label takes the accent's ink
                readonly property bool onIndicator: current && (root.indicatorShape === "pill" || root.indicatorShape === "mark")
                readonly property color tint: ws.urgent ? root.urgentTint : current ? root.focusTint : hot ? Theme.mix(root.occupiedTint, root.focusTint, 0.5) : occupied ? root.occupiedTint : root.emptyTint

                x: root.vertical ? 0 : modelData.from
                y: root.vertical ? modelData.from : 0
                width: root.vertical ? root.thick : modelData.len
                height: root.vertical ? modelData.len : root.thick
                Glide on x {}
                Glide on y {}
                Glide on width {}
                Glide on height {}

                // hover
                Rectangle {
                    anchors.fill: parent
                    visible: root.style !== "pills" && root.style !== "dots"
                    radius: Math.min(width, height) / 2
                    color: cellItem.hot && !cellItem.current ? Theme.hover : "transparent"
                    Behavior on color {
                        ColorAnim {}
                    }
                }

                // the mark: pills and dots draw every workspace; filled when occupied, a ring when empty
                Rectangle {
                    visible: (root.style === "pills" || root.style === "dots") && !(cellItem.current && root.indicatorShape !== "line" && root.indicatorShape !== "ring")
                    anchors.centerIn: parent
                    width: root.vertical ? root.mark : cellItem.modelData.len
                    height: root.vertical ? cellItem.modelData.len : root.mark
                    radius: Math.min(width, height) / 2
                    color: cellItem.occupied || cellItem.ws.urgent ? Theme.alpha(cellItem.tint, cellItem.ws.urgent ? 1 : 0.6) : "transparent"
                    border.width: cellItem.occupied ? 0 : Math.max(1, root.mark * 0.2)
                    border.color: Theme.alpha(cellItem.tint, root.emptyOpacity + 0.2)
                    Behavior on color {
                        ColorAnim {}
                    }
                }

                // label and app icons
                Grid {
                    anchors.centerIn: parent
                    columns: root.vertical ? 1 : 8
                    spacing: 2
                    horizontalItemAlignment: Grid.AlignHCenter
                    verticalItemAlignment: Grid.AlignVCenter
                    Text {
                        visible: text !== ""
                        text: cellItem.modelData.label
                        font.family: root.family
                        font.pixelSize: Math.round(root.cell * 0.46 * root.fontScale)
                        font.weight: cellItem.current ? Font.DemiBold : Font.Normal
                        color: cellItem.onIndicator ? Theme.onAccent : cellItem.current || cellItem.occupied || cellItem.ws.urgent ? (cellItem.ws.urgent ? root.urgentTint : root.labelTint) : Theme.alpha(root.labelTint, root.emptyOpacity)
                        Behavior on color {
                            ColorAnim {}
                        }
                    }
                    Repeater {
                        model: cellItem.modelData.icons
                        delegate: Image {
                            required property string modelData
                            width: root.iconSize
                            height: root.iconSize
                            sourceSize.width: width * 2
                            sourceSize.height: height * 2
                            source: modelData
                            asynchronous: true
                            opacity: cellItem.current ? 1 : 0.8
                        }
                    }
                }

                // an urgent workspace breathes until it is visited
                SequentialAnimation on opacity {
                    running: cellItem.ws.urgent && root.opt("urgent_pulse") !== false && !Motion.reduced
                    loops: Animation.Infinite
                    alwaysRunToEnd: true
                    NumberAnimation {
                        to: 0.45
                        duration: 520
                        easing.type: Easing.InOutSine
                    }
                    NumberAnimation {
                        to: 1
                        duration: 520
                        easing.type: Easing.InOutSine
                    }
                }

                MouseArea {
                    id: area
                    anchors.fill: parent
                    anchors.margins: -root.gap / 2
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    // left click goes there; the other buttons and the wheel are the widget's actions
                    acceptedButtons: Qt.LeftButton
                    onClicked: cellItem.ws.activate()
                }
            }
        }
    }
}
