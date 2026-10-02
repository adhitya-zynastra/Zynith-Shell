import QtQuick
import qs.Common
import qs.Components
import qs.Services

// Opens the Control Panel; the glyph shows the active Experience profile.
BarItem {
    id: root

    readonly property var glyphs: ({
            performance: "leaf",
            balanced: "gauge",
            enhanced: "sparkles",
            max: "rocket"
        })

    active: PanelRouter.isOpen("control", screen?.name ?? "")
    onClicked: bar?.openPanel("control", root)

    Icon {
        name: root.glyphs[ExperiencePolicy.profile] ?? "adjustments-horizontal"
        tone: root.active ? "accent" : "ink"
    }
}
