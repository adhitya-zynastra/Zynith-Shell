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
            quick: control,
            control: control,
            visualizer: visualizer,
            launcher: launcher,
            tray: tray,
            bluetooth: bluetooth,
            brightness: brightness,
            power: power,
            session: session,
            notifications: notifications,
            keyboard: keyboard,
            divider: divider,
            wallpaper: wallpaper,
            nightlight: nightlight
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
    readonly property Component control: Component {
        ControlWidget {}
    }
    readonly property Component launcher: Component {
        LauncherButton {}
    }
    readonly property Component tray: Component {
        TrayWidget {}
    }
    readonly property Component bluetooth: Component {
        BluetoothWidget {}
    }
    readonly property Component brightness: Component {
        BrightnessWidget {}
    }
    readonly property Component power: Component {
        PowerProfileWidget {}
    }
    readonly property Component session: Component {
        SessionWidget {}
    }
    readonly property Component notifications: Component {
        NotificationsWidget {}
    }
    readonly property Component keyboard: Component {
        KeyboardWidget {}
    }
    readonly property Component divider: Component {
        DividerWidget {}
    }
    readonly property Component wallpaper: Component {
        WallpaperButton {}
    }
    readonly property Component nightlight: Component {
        NightlightWidget {}
    }
    readonly property Component visualizer: Component {
        VisualizerWidget {}
    }
}
