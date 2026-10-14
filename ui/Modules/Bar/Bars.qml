import QtQuick
import Quickshell
import qs.Services
import "../../Common/BarModel.js" as BarModel

// Every configured bar, on every output it targets ("*" = all), and per output the room the bars on each edge keep
// windows out of (one EdgeReserve per edge that keeps any).
Scope {
    Variants {
        model: Quickshell.screens
        delegate: Scope {
            id: outputScope
            required property var modelData
            readonly property var reserved: BarModel.reservations(Config.bars, modelData.name)
            Variants {
                model: BarModel.edges.filter(e => outputScope.reserved[e] > 0)
                delegate: EdgeReserve {
                    required property var modelData
                    screen: outputScope.modelData
                    edge: modelData
                    depth: outputScope.reserved[modelData]
                }
            }
        }
    }
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
