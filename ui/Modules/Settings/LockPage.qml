import QtQuick
import qs.Common
import qs.Components
import qs.Services

// The lock screen itself stays with the native shell (session lock and PAM); these are the preferences the
// Zynith side already owns.
Column {
    spacing: Metrics.s5

    PanelHeader {
        width: parent.width
        title: "Lock screen"
        caption: "Locking and unlocking stay with the native shell's secure path"
    }

    Card {
        width: parent.width
        caption: "What it shows"

        SettingToggle {
            title: "Hide notification content"
            detail: "Show only that something arrived, not what it says"
            domain: "notifications"
            key: "lock_redaction"
        }
        SettingChoice {
            title: "Wallpaper"
            detail: "The live wallpaper's poster; a live lock screen comes later"
            domain: "wallpaper"
            key: "lock"
            options: [{ key: "poster", label: "Poster" }]
        }
    }
}
