import QtQuick
import qs.Common
import qs.Components
import qs.Services

Column {
    spacing: Metrics.s5

    PanelHeader {
        width: parent.width
        title: "Media"
        caption: Media.present ? "Playing: " + Media.title + (Media.artist ? " · " + Media.artist : "") : "Nothing playing"
    }

    Card {
        width: parent.width
        caption: "Visualizer"

        SettingSlider {
            title: "Bars"
            detail: "0 turns the visualizer off; the profile decides when unset"
            domain: "experience"
            key: "overrides.visualizerBands"
            from: 0
            to: 64
            step: 4
            format: v => v === 0 ? "Off" : Math.round(v)
        }
        SettingSlider {
            title: "Frame rate"
            detail: "Each frame redraws its bar; 30 is smooth, 60 costs twice as much"
            domain: "experience"
            key: "overrides.visualizerFps"
            from: 15
            to: 60
            step: 5
            format: v => Math.round(v) + " fps"
        }
    }
}
