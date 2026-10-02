import QtQuick
import qs.Common
import qs.Components
import qs.Services

Column {
    spacing: Metrics.s5

    PanelHeader {
        width: parent.width
        title: "Notifications"
        caption: Notifications.serving ? "Zynith handles notifications" : "The native shell handles notifications"
    }

    Card {
        width: parent.width
        caption: "Popups"

        SettingChoice {
            title: "Where"
            domain: "notifications"
            key: "location"
            controlWidth: 360
            options: [{ key: "top-left", label: "Top left" }, { key: "top-center", label: "Top" }, { key: "top-right", label: "Top right" }, { key: "bottom-right", label: "Bottom right" }]
        }
        SettingChoice {
            title: "Density"
            domain: "notifications"
            key: "density"
            options: [{ key: "comfortable", label: "Comfortable" }, { key: "compact", label: "Compact" }]
        }
        SettingSlider {
            title: "How long they stay"
            detail: "Critical notifications stay until handled"
            domain: "notifications"
            key: "popup_ms"
            from: 2000
            to: 15000
            step: 500
            format: v => (v / 1000).toFixed(1) + " s"
        }
        SettingSlider {
            title: "At most on screen"
            domain: "notifications"
            key: "max_popups"
            from: 1
            to: 8
            step: 1
            format: v => Math.round(v)
        }
    }

    Card {
        width: parent.width
        caption: "Behaviour"

        SettingToggle {
            title: "Do not disturb"
            detail: "Hold popups back; critical ones still show"
            domain: "notifications"
            key: "dnd"
        }
        SettingToggle {
            title: "Group by app"
            domain: "notifications"
            key: "grouping"
        }
        SettingToggle {
            title: "Sound"
            domain: "notifications"
            key: "sound"
        }
        SettingSlider {
            title: "Sound volume"
            domain: "notifications"
            key: "sound_volume"
        }
        SettingToggle {
            title: "Hide content on the lock screen"
            domain: "notifications"
            key: "lock_redaction"
        }
    }
}
