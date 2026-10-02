import QtQuick
import QtQuick.Effects
import qs.Common
import qs.Services

// The base surface: a tinted sheet with a hairline edge and a faint top sheen. The compositor blurs
// what is behind it when the window registers a blur region (see BlurRegion); this item only paints.
Item {
    id: root

    property real radius: Metrics.radiusLg
    property color fill: Theme.glass
    property bool raised: false
    property bool sheen: ExperiencePolicy.effectsQuality !== "minimal"
    readonly property alias sheet: sheet

    MultiEffect {
        anchors.fill: sheet
        source: sheet
        visible: ExperiencePolicy.shadows && root.raised
        shadowEnabled: true
        shadowColor: Theme.shadow
        shadowBlur: ExperiencePolicy.shadowQuality === "layered" ? 1.0 : 0.7
        shadowVerticalOffset: ExperiencePolicy.shadowQuality === "layered" ? 6 : 3
        blurMax: 32
        autoPaddingEnabled: true
    }

    Rectangle {
        id: sheet

        anchors.fill: parent
        radius: root.radius
        color: root.fill
        border.width: Metrics.hairline
        border.color: Theme.hairline

        Rectangle {
            visible: root.sheen
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                leftMargin: root.radius
                rightMargin: root.radius
                topMargin: 1
            }
            height: 1
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop {
                    position: 0
                    color: "transparent"
                }
                GradientStop {
                    position: 0.5
                    color: Theme.sheen
                }
                GradientStop {
                    position: 1
                    color: "transparent"
                }
            }
        }
    }
}
