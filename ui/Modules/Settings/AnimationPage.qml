import QtQuick
import qs.Common
import qs.Components
import qs.Services

Column {
    spacing: Metrics.s5

    PanelHeader {
        width: parent.width
        title: "Animation"
        caption: "How surfaces arrive, move and leave"
    }

    Card {
        width: parent.width
        caption: "Motion"

        SettingSlider {
            title: "Duration"
            detail: "Multiplies every animation; lower is faster"
            domain: "animation"
            key: "speed"
            from: 0.5
            to: 2
            format: v => "× " + v.toFixed(2)
        }
        SettingChoice {
            title: "Style"
            detail: "Fluid decelerates long; crisp is short and even; calm is soft both ways"
            domain: "animation"
            key: "style"
            options: [{ key: "fluid", label: "Fluid" }, { key: "crisp", label: "Crisp" }, { key: "calm", label: "Calm" }]
        }
        SettingToggle {
            title: "Reduce motion"
            detail: "Changes happen at once, without travel or scaling"
            domain: "animation"
            key: "reduced_motion"
        }
    }
}
