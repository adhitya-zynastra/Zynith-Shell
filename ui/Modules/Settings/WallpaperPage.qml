import QtQuick
import qs.Common
import qs.Components
import qs.Services

Column {
    spacing: Metrics.s5

    PanelHeader {
        width: parent.width
        title: "Wallpaper"
        caption: "One wallpaper state drives the desktop, the overview, the lock screen and the colours"
    }

    Card {
        width: parent.width
        caption: "Images"

        SettingText {
            title: "Folder"
            detail: "Where the wallpaper browser looks"
            domain: "wallpaper"
            key: "directory"
            placeholder: "~/Pictures/wallpapers"
        }
    }

    Card {
        width: parent.width
        caption: "Live wallpaper"

        SettingChoice {
            title: "Overview"
            detail: "Live shows the running wallpaper behind niri's overview; Poster shows its still image, which costs nothing"
            domain: "wallpaper"
            key: "overview"
            options: [{ key: "poster", label: "Poster" }, { key: "live", label: "Live" }]
        }
        SettingChoice {
            title: "Lock screen"
            detail: "The lock screen shows the poster for now"
            domain: "wallpaper"
            key: "lock"
            options: [{ key: "poster", label: "Poster" }]
        }
    }
}
