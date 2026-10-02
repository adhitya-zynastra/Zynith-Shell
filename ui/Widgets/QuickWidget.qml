import QtQuick
import qs.Common
import qs.Components
import qs.Services

// Opens the Home panel; its glyph shows the active Experience Profile.
BarItem {
    id: root

    readonly property var glyphs: ({
            performance: "leaf",
            balanced: "gauge",
            enhanced: "sparkles",
            max: "rocket"
        })

    active: PanelRouter.isOpen("home", screen?.name ?? "")
    onClicked: bar?.openPanel("home", root)

    Icon {
        name: root.glyphs[ExperiencePolicy.profile] ?? "adjustments-horizontal"
        tone: root.active ? "accent" : "ink"
    }
}
