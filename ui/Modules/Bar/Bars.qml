import QtQuick
import Quickshell
import qs.Services

// Every configured bar, on every output it targets ("*" = all).
Scope {
    Variants {
        model: Config.bars.filter(b => b.enabled !== false)

        delegate: Scope {
            id: barScope

            required property var modelData
            readonly property var targets: modelData.screens ?? ["*"]

            Variants {
                model: Quickshell.screens.filter(s => barScope.targets.includes("*") || barScope.targets.includes(s.name))

                delegate: BarWindow {
                    spec: barScope.modelData
                }
            }
        }
    }
}
