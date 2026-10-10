import QtQuick
import Quickshell
import Zynith.Native
import qs.Common
import qs.Components
import qs.Services

// The native shell's workspaces, reproduced one to one (styles regular · minimal · focus_hint) — the baseline.
// The workspaces: pills that stretch for the active one (regular), dots (minimal), or a quiet line that
// only marks focus (focus_hint); their numbers or names, their windows' app icons, all as configured.
// Left click on a workspace goes there (reserved); the wheel switches (its actions).
BarItem {
    id: root

    readonly property var sets: Workspaces.forScreen(screen, opt("show_all_outputs") === true).filter(w => !(opt("hide_when_empty") === true && w.windows === 0 && !w.active))
    readonly property string style: opt("style") ?? "regular"
    readonly property real unit: 6 * (opt("pill_scale") ?? 1) * sizeScale
    readonly property bool labels: opt("show_labels") !== false
    readonly property bool onFocusedOnly: opt("focused_output_only") === true
    shown: sets.length > 0 && !(onFocusedOnly && Workspaces.focusedOutput !== (screen?.name ?? ""))
    pad: Metrics.s2
    spacing: Metrics.s1 * 1.5

    // windowList() is a call, asked again only when the windows' shape changes (opened, closed, moved, focus
    // moved) — never for a title — and only when icons are shown
    readonly property var windows: {
        NiriState.windowsRevision;
        NiriState.focusedId;
        return opt("show_icons") === true ? NiriState.windowList() : [];
    }
    function iconsFor(id: var): var {
        return windows.filter(w => w.workspaceId === id).slice(0, 4).map(w => {
            const entry = DesktopEntries.heuristicLookup(w.appId);
            return Quickshell.iconPath(entry?.icon ?? w.appId, true);
        }).filter(s => s !== "");
    }

    Repeater {
        model: root.sets

        delegate: Item {
            id: mark

            required property var modelData
            readonly property bool current: modelData.active
            readonly property bool occupied: modelData.windows > 0
            readonly property bool hot: hover.containsMouse && root.opt("change_color_on_hover") !== false
            // as the native workspaces: focused, urgent, occupied in their colours; empty in its colour at
            // empty_opacity (native 0.55)
            readonly property color tint: modelData.urgent ? Theme.colour(root.opt("urgent_color") ?? "error") : current || hot ? Theme.colour(root.opt("focused_color") ?? "primary") : occupied ? Theme.colour(root.opt("occupied_color") ?? "secondary") : Theme.alpha(Theme.colour(root.opt("empty_color") ?? "secondary"), root.opt("empty_opacity") ?? 0.55)
            readonly property string label: {
                if (!root.labels || (root.opt("labels_only_when_occupied") === true && !occupied && !current))
                    return "";
                const raw = root.opt("label_source") === "name" && modelData.name !== "" ? modelData.name : String(modelData.idx);
                return raw.slice(0, root.opt("max_label_chars") ?? 1);
            }
            readonly property var icons: root.opt("show_icons") !== false && root.style === "regular" ? root.iconsFor(modelData.key) : []
            readonly property real length: root.style === "minimal" ? root.unit : root.unit * (current ? (root.opt("active_pill_size") ?? 2.2) : (root.opt("inactive_pill_size") ?? 1)) * 2 + (label !== "" ? 10 : 0) + icons.length * (root.unit * 2 + 2)

            width: root.vertical ? root.cross - 4 : Math.max(length, root.unit * 2)
            height: root.vertical ? Math.max(length, root.unit * 2) : root.cross - 4

            Rectangle {
                anchors.centerIn: parent
                visible: root.style !== "focus_hint" || mark.current
                width: root.vertical ? (root.style === "minimal" ? root.unit : root.unit * 2.4) : mark.length
                height: root.vertical ? mark.length : (root.style === "minimal" ? root.unit : root.unit * 2.4)
                // capsule_radius (native): px, held to round; -1 round
                radius: (root.opt("capsule_radius") ?? -1) >= 0 ? Math.min(root.opt("capsule_radius"), Math.min(width, height) / 2) : Math.min(width, height) / 2
                color: root.style === "focus_hint" ? "transparent" : mark.tint
                border.width: root.style === "focus_hint" ? 1.5 : 0
                border.color: mark.tint

                Glide on width {}
                Glide on height {}
                Behavior on color {
                    ColorAnim {}
                }

                Row {
                    anchors.centerIn: parent
                    spacing: 2
                    visible: !root.vertical
                    Text {
                        visible: mark.label !== ""
                        anchors.verticalCenter: parent.verticalCenter
                        text: mark.label
                        font.family: root.family
                        font.pixelSize: Math.round(9 * root.fontScale * root.sizeScale)
                        font.bold: mark.current
                        color: mark.current && root.style !== "focus_hint" ? Theme.onAccent : mark.tint
                    }
                    Repeater {
                        model: mark.icons
                        delegate: Image {
                            required property string modelData
                            anchors.verticalCenter: parent.verticalCenter
                            width: root.unit * 2
                            height: width
                            sourceSize.width: width * 2
                            sourceSize.height: height * 2
                            source: modelData
                            asynchronous: true
                        }
                    }
                }
            }

            MouseArea {
                id: hover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                // left click goes there; the other buttons and the wheel are the widget's actions
                acceptedButtons: Qt.LeftButton
                onClicked: mark.modelData.activate()
            }
        }
    }
}
