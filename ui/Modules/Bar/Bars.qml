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
    // Keyed by the bar's id, not by its settings: Variants keeps an instance only while its model value is equal,
    // and a bar's settings as the value made every change (each tick of a slider) destroy the bar's window and
    // create a new Wayland surface. Now a change reaches the same window through `spec`; only showing, hiding or
    // deleting a bar (or moving it to other screens) creates or destroys one.
    Variants {
        model: Config.bars.filter(b => b.enabled !== false).map(b => b.id)

        delegate: Scope {
            id: barScope

            required property var modelData
            readonly property var live: Config.bars.find(b => b.id === modelData) ?? null
            // the last settings seen: for the moment between the bar leaving the list and this scope going
            property var spec: live
            onLiveChanged: if (live)
                spec = live
            readonly property var targets: BarModel.list(spec?.screens ?? ["*"])

            Variants {
                model: barScope.spec ? Quickshell.screens.filter(s => barScope.targets.includes("*") || barScope.targets.includes(s.name)) : []

                delegate: BarWindow {
                    spec: barScope.spec
                }
            }
        }
    }
}
