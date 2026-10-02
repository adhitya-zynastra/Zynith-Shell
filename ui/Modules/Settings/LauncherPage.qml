import QtQuick
import qs.Common
import qs.Components
import qs.Services

Column {
    spacing: Metrics.s5

    PanelHeader {
        width: parent.width
        title: "Launcher"
        caption: "= calculate · > windows · @ wallpapers · : emoji · ! session"
    }

    Card {
        width: parent.width
        caption: "Layout"

        SettingChoice {
            title: "Position"
            domain: "panels"
            key: "launcher.position"
            options: [{ key: "center", label: "Centre" }, { key: "top", label: "Top" }]
        }
        SettingChoice {
            title: "Density"
            domain: "panels"
            key: "launcher.density"
            options: [{ key: "comfortable", label: "Comfortable" }, { key: "compact", label: "Compact" }]
        }
        SettingSlider {
            title: "Width"
            domain: "panels"
            key: "launcher.width"
            from: 480
            to: 900
            step: 20
            format: v => Math.round(v) + " px"
        }
        SettingSlider {
            title: "Results shown"
            domain: "panels"
            key: "launcher.rows"
            from: 4
            to: 14
            step: 1
            format: v => Math.round(v)
        }
    }
}
