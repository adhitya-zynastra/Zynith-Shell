import QtQuick
import Zynith.Native
import qs.Common
import qs.Components
import qs.Services

// Luau plugins and what each may do. A plugin gets a capability only when it declares it and it is granted here.
Column {
    id: root
    spacing: Metrics.s5

    property var plugins: []   // [{ id, version, enabled, declared: [], granted: [] }]
    readonly property var capabilityNames: ["exec", "shell", "network", "files", "notifications", "clipboard", "env"]

    function parseCaps(text: string): var {
        return text === "none" ? [] : text.split(",").map(s => s.trim()).filter(s => s);
    }
    function refresh(): void {
        CoreClient.call("plugins list", list => {
            const rows = list.split("\n").filter(l => l.trim() !== "").map(l => {
                const parts = l.split(" ");
                return { id: parts[0], version: parts[2] ?? "", enabled: l.includes(" enabled"), declared: [], granted: [] };
            });
            CoreClient.call("plugins capabilities", caps => {
                for (const line of caps.split("\n")) {
                    const m = line.match(/^(\S+) declared (.*) · granted (.*) · effective (.*)$/);
                    const row = m ? rows.find(r => r.id === m[1]) : null;
                    if (row) {
                        row.declared = root.parseCaps(m[2]);
                        row.granted = root.parseCaps(m[3]);
                    }
                }
                root.plugins = rows.filter(r => r.enabled).concat(rows.filter(r => !r.enabled));
            });
        });
    }
    Component.onCompleted: refresh()

    PanelHeader {
        width: parent.width
        title: "Plugins"
        caption: plugins.filter(p => p.enabled).length + " enabled of " + plugins.length
    }

    Repeater {
        model: root.plugins.filter(p => p.enabled)
        delegate: Card {
            id: pluginCard
            required property var modelData
            width: root.width
            caption: modelData.id + "  ·  " + modelData.version

            Label {
                visible: pluginCard.modelData.declared.length === 0
                role: "label"
                tone: "faint"
                text: "Declares no capabilities: it can only draw and use its own folder"
            }
            Repeater {
                model: pluginCard.modelData.declared
                delegate: SettingRow {
                    id: capRow
                    required property string modelData
                    readonly property bool granted: pluginCard.modelData.granted.includes(modelData)
                    title: modelData
                    detail: modelData === "exec" || modelData === "shell" ? "Runs programs as you: full trust" : ""
                    controlWidth: 44
                    Toggle {
                        anchors.right: parent.right
                        checked: capRow.granted
                        onToggled: CoreClient.call("plugins " + (capRow.granted ? "revoke " : "grant ") + pluginCard.modelData.id + " " + capRow.modelData, () => root.refresh())
                    }
                }
            }
        }
    }

    Card {
        width: parent.width
        caption: "Installed, not enabled"
        Label {
            width: parent.width
            role: "label"
            tone: "faint"
            wrapMode: Text.WordWrap
            elide: Text.ElideNone
            text: root.plugins.filter(p => !p.enabled).map(p => p.id).join("  ·  ")
        }
    }
}
