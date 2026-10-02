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
        caption: "Browser"

        SettingChoice {
            title: "Layout"
            detail: "Carousel: a cinematic arc across the dimmed desktop. Grid: a panel with the focused wallpaper above a grid. L switches while browsing"
            domain: "wallpaper"
            key: "layout"
            options: [{ key: "carousel", label: "Carousel" }, { key: "grid", label: "Grid" }]
        }
        SettingSlider {
            title: "Carousel card"
            detail: "Width of the focused card; Auto is 40 % of the screen, at most 760 px"
            domain: "wallpaper"
            key: "card_width"
            from: 0
            to: 1400
            step: 20
            format: v => v < 320 ? "Auto" : Math.round(v) + " px"
        }
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
