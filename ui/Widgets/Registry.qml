pragma Singleton

import QtQuick
import Quickshell

// Bar widget kinds by their native names (BarWidgetTypes holds their settings and gestures). A kind is
// one implementation; where it is placed and how it behaves is configuration.
Singleton {
    readonly property var types: ({
            "launcher": glyphButton,
            "control-center": glyphButton,
            "clipboard": glyphButton,
            "wallpaper": glyphButton,
            "screenshot": glyphButton,
            "settings": glyphButton,
            "session": glyphButton,
            "custom_button": glyphButton,
            "workspaces": workspaces,
            "taskbar": taskbar,
            "active_window": activeWindow,
            "clock": clock,
            "media": media,
            "audio_visualizer": visualizer,
            "tray": tray,
            "network": network,
            "bluetooth": bluetooth,
            "volume": volume,
            "brightness": brightness,
            "battery": battery,
            "power_profile": power,
            "notifications": notifications,
            "keyboard_layout": keyboard,
            "lock_keys": lockKeys,
            "privacy": privacy,
            "sysmon": sysmon,
            "weather": weather,
            "nightlight": nightlight,
            "caffeine": caffeine,
            "theme_mode": themeMode,
            "text": text,
            "spacer": spacer,
            "divider": divider
        })

    function component(type: string): Component {
        return types[type] ?? null;
    }

    readonly property Component glyphButton: Component {
        GlyphButtonWidget {}
    }
    readonly property Component workspaces: Component {
        WorkspacesWidget {}
    }
    // the native shell's own workspace styles, reproduced one to one (the baseline)
    readonly property Component workspacesClassic: Component {
        WorkspacesClassicWidget {}
    }
    readonly property Component taskbar: Component {
        TaskbarWidget {}
    }
    readonly property Component activeWindow: Component {
        ActiveWindowWidget {}
    }
    readonly property Component clock: Component {
        ClockWidget {}
    }
    readonly property Component media: Component {
        MediaWidget {}
    }
    readonly property Component visualizer: Component {
        VisualizerWidget {}
    }
    readonly property Component tray: Component {
        TrayWidget {}
    }
    readonly property Component network: Component {
        NetworkWidget {}
    }
    readonly property Component bluetooth: Component {
        BluetoothWidget {}
    }
    readonly property Component volume: Component {
        VolumeWidget {}
    }
    readonly property Component brightness: Component {
        BrightnessWidget {}
    }
    readonly property Component battery: Component {
        BatteryWidget {}
    }
    readonly property Component power: Component {
        PowerProfileWidget {}
    }
    readonly property Component notifications: Component {
        NotificationsWidget {}
    }
    readonly property Component keyboard: Component {
        KeyboardWidget {}
    }
    readonly property Component lockKeys: Component {
        LockKeysWidget {}
    }
    readonly property Component privacy: Component {
        PrivacyWidget {}
    }
    readonly property Component sysmon: Component {
        SysmonWidget {}
    }
    readonly property Component weather: Component {
        WeatherWidget {}
    }
    readonly property Component nightlight: Component {
        NightlightWidget {}
    }
    readonly property Component caffeine: Component {
        CaffeineWidget {}
    }
    readonly property Component themeMode: Component {
        ThemeModeWidget {}
    }
    readonly property Component text: Component {
        TextWidget {}
    }
    readonly property Component spacer: Component {
        SpacerWidget {}
    }
    readonly property Component divider: Component {
        DividerWidget {}
    }
}
