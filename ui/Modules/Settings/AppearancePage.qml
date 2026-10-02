import QtQuick
import qs.Common
import qs.Components
import qs.Services

// How every surface looks: the wallpaper's colours, how strongly they tint, glass, edges, shape and type.
Column {
    spacing: Metrics.s5

    PanelHeader {
        width: parent.width
        title: "Appearance"
        caption: Scheme.live ? "Colours come from the wallpaper" : "Default colours (the theme engine has not written a palette yet)"
    }

    Card {
        width: parent.width
        caption: "Palette"

        Flow {
            width: parent.width
            spacing: Metrics.s3

            Repeater {
                model: [["Accent", Theme.accent], ["Secondary", Theme.secondary], ["Base", Theme.base], ["Surface", Theme.surfaceLow], ["Raised", Theme.surfaceHigh], ["Ink", Theme.ink], ["Muted", Theme.inkMuted], ["Edge", Theme.hairline], ["Danger", Theme.danger]]
                delegate: Column {
                    required property var modelData
                    spacing: Metrics.s1
                    Rectangle {
                        width: 64
                        height: 40
                        radius: Metrics.radiusMd
                        color: parent.modelData[1]
                        border.width: 1
                        border.color: Theme.hairline
                    }
                    Label {
                        width: 64
                        role: "micro"
                        tone: "faint"
                        text: parent.modelData[0]
                    }
                }
            }
        }
    }

    Card {
        width: parent.width
        caption: "Colour"

        SettingSlider {
            title: "Wallpaper tint"
            detail: "How far surfaces lean toward the wallpaper's colour instead of neutral grey"
            domain: "appearance"
            key: "tint"
        }
        SettingChoice {
            title: "Accent"
            detail: "The one highlight colour"
            domain: "appearance"
            key: "accent"
            options: [{ key: "wallpaper", label: "Wallpaper" }, { key: "#b4c5ff", label: "Blue" }, { key: "#e2bbdb", label: "Rose" }, { key: "#c5d6a8", label: "Sage" }]
        }
        SettingChoice {
            title: "Contrast"
            domain: "appearance"
            key: "contrast"
            options: [{ key: "standard", label: "Standard" }, { key: "high", label: "High" }]
        }
    }

    Card {
        width: parent.width
        caption: "Surfaces"

        SettingSlider {
            title: "Surface opacity"
            detail: "0 lets the Experience profile decide"
            domain: "appearance"
            key: "surface_opacity"
            format: v => v === 0 ? "Profile" : Math.round(v * 100) + "%"
        }
        SettingChoice {
            title: "Blur behind surfaces"
            domain: "appearance"
            key: "blur"
            options: [{ key: "profile", label: "Profile" }, { key: "on", label: "On" }, { key: "off", label: "Off" }]
        }
        SettingChoice {
            title: "Edges"
            domain: "appearance"
            key: "border"
            options: [{ key: "none", label: "None" }, { key: "subtle", label: "Subtle" }, { key: "defined", label: "Defined" }]
        }
        SettingSlider {
            title: "Corner radius"
            domain: "appearance"
            key: "radius"
            from: 0.5
            to: 1.5
            format: v => "× " + v.toFixed(2)
        }
    }

    Card {
        width: parent.width
        caption: "Type"

        SettingSlider {
            title: "Text size"
            domain: "appearance"
            key: "font_scale"
            from: 0.85
            to: 1.3
            format: v => "× " + v.toFixed(2)
        }
    }
}
