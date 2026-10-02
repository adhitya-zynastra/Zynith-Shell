import QtQuick
import qs.Common
import qs.Components
import qs.Services

Column {
    spacing: Metrics.s5

    PanelHeader {
        width: parent.width
        title: "Appearance"
        caption: Palette.live ? "Colours from the wallpaper" : "Default colours (no palette from the theme engine yet)"
    }

    Card {
        width: parent.width
        caption: "Palette"

        Flow {
            width: parent.width
            spacing: Metrics.s3

            Repeater {
                model: ["primary", "secondary", "tertiary", "surface", "surface_container_low", "surface_container_high", "on_surface", "on_surface_variant", "outline_variant", "error"]
                delegate: Column {
                    required property string modelData
                    spacing: Metrics.s1
                    Rectangle {
                        width: 64
                        height: 40
                        radius: Metrics.radiusMd
                        color: Theme.pal(parent.modelData)
                        border.width: Metrics.hairline
                        border.color: Theme.hairline
                    }
                    Label {
                        width: 64
                        role: "micro"
                        tone: "faint"
                        text: parent.modelData.replace(/_/g, " ")
                    }
                }
            }
        }
        Label {
            width: parent.width
            visible: Palette.image !== ""
            role: "caption"
            tone: "faint"
            text: "Source: " + Palette.image
        }
    }

    Card {
        width: parent.width
        caption: "Glass"

        Label {
            width: parent.width
            role: "body"
            tone: "muted"
            wrapMode: Text.WordWrap
            elide: Text.ElideNone
            text: "Surfaces are tinted glass over a compositor blur (" + ExperiencePolicy.blurQuality + "). Blur strength itself is niri's, set under Personalization → Glass in the native settings for now."
        }
    }
}
