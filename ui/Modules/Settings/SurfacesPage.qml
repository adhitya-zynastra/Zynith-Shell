import QtQuick
import Zynith.Native
import qs.Common
import qs.Components
import qs.Services

// Which visible surfaces Zynith draws and which the native shell still does. Switching one back is the
// rollback for that surface.
Column {
    id: root
    spacing: Metrics.s5

    readonly property var surfaces: [
        { id: "bar", label: "Bars", detail: "Applied at once" },
        { id: "notifications", label: "Notifications", detail: "Also set [notification] enable_daemon in rice.toml to match" },
        { id: "osd", label: "On-screen display", detail: "Also set [osd] enabled in rice.toml to match" },
        { id: "desktop_widgets", label: "Desktop widgets" },
        { id: "control_center", label: "Control Panel", detail: "Native requests for its Control Center (hot corners, its keys) come here" },
        { id: "launcher", label: "Launcher" },
        { id: "wallpaper", label: "Wallpaper browser" },
        { id: "clipboard", label: "Clipboard" },
        { id: "session", label: "Session menu" }
    ]

    PanelHeader {
        width: parent.width
        title: "Zynith UI"
        caption: "Surfaces drawn by Zynith; the native shell keeps every service behind them"
    }

    Card {
        width: parent.width
        caption: "Surfaces"

        Repeater {
            model: root.surfaces
            delegate: SettingRow {
                required property var modelData
                title: modelData.label
                detail: modelData.detail ?? ""
                domain: "zynith"
                key: "surfaces." + modelData.id
                controlWidth: 200

                Segmented {
                    width: parent.width
                    current: String(parent.parent.value)
                    options: [{ key: "zynith", label: "Zynith" }, { key: "native", label: "Native" }]
                    onPicked: key => {
                        parent.parent.write(key);
                        CoreClient.call("surfaces-sync");
                    }
                }
            }
        }
    }
}
