pragma Singleton

import QtQuick
import Quickshell

// Widget types by config name. A widget type is one implementation; where it is placed is config.
Singleton {
    readonly property var types: ({
            clock: clock,
            workspaces: workspaces,
            media: media,
            audio: audio,
            network: network,
            battery: battery,
            quick: quick,
            visualizer: visualizer
        })

    function component(type: string): Component {
        return types[type] ?? null;
    }

    readonly property Component clock: Component {
        ClockWidget {}
    }
    readonly property Component workspaces: Component {
        WorkspacesWidget {}
    }
    readonly property Component media: Component {
        MediaWidget {}
    }
    readonly property Component audio: Component {
        AudioWidget {}
    }
    readonly property Component network: Component {
        NetworkWidget {}
    }
    readonly property Component battery: Component {
        BatteryWidget {}
    }
    readonly property Component quick: Component {
        QuickWidget {}
    }
    readonly property Component visualizer: Component {
        VisualizerWidget {}
    }
}
