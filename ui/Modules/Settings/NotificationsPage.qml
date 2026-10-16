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
            options: [{ key: "top-left", label: "Top left" }, { key: "top-center", label: "Top" }, { key: "top-right", label: "Top right" }, { key: "bottom-left", label: "Bottom left" }, { key: "bottom-center", label: "Bottom" }, { key: "bottom-right", label: "Bottom right" }]
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

    // the rest of what the native notifications had, and the history
    Card {
        width: parent.width
        caption: "Placement and history"
        SchemaForm {
            width: parent.width
            readonly property var own: notificationsDomain.values
            schema: [
                { key: "margin_x", label: "From the side", kind: "int", default: 10, from: 0, to: 200, step: 1 },
                { key: "margin_y", label: "From the top or bottom", kind: "int", default: 6, from: 0, to: 200, step: 1 },
                { key: "layer", label: "Above", kind: "choice", default: "overlay", options: [{ key: "top", label: "Windows" }, { key: "overlay", label: "Everything" }] },
                { key: "monitor", label: "On", kind: "choice", default: "focused", options: [{ key: "focused", label: "The focused screen" }, { key: "primary", label: "The first screen" }] },
                { key: "show_app_name", label: "App name", kind: "toggle", default: true },
                { key: "show_actions", label: "Action buttons", kind: "toggle", default: true },
                { key: "keep_dismissed", label: "Closed popups stay in the history", kind: "toggle", default: true },
                { key: "history_persist", label: "History survives restarts", kind: "toggle", default: true },
                { key: "history_retention_hours", label: "Forget after (hours, 0 never)", kind: "int", default: 0, from: 0, to: 720, step: 1 },
                { key: "history_size", label: "History holds", kind: "int", default: 100, from: 10, to: 1000, step: 10 }
            ]
            valueOf: key => own[key] ?? schema.find(s => s.key === key)?.default
            isSet: key => own[key] !== undefined && own[key] !== schema.find(s => s.key === key)?.default
            onChanged: (key, value) => Config.change("notifications", key, value, labelOf(key))
            onCleared: key => Config.change("notifications", key, undefined, labelOf(key))
        }
    }
    QtObject {
        id: notificationsDomain
        readonly property var values: Config.files.notifications.values
    }
}
