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
    // the hairline around the sheet
    property bool edge: true
    // per-corner radii [top left, top right, bottom right, bottom left]; null: `radius` everywhere
    property var corners: null
    // the edge's colour (a palette role or #hex; empty: the theme's hairline) and width (-1: the theme's)
    property string edgeColor: ""
    property real edgeWidth: -1
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
        topLeftRadius: root.corners ? root.corners[0] : -1
        topRightRadius: root.corners ? root.corners[1] : -1
        bottomRightRadius: root.corners ? root.corners[2] : -1
        bottomLeftRadius: root.corners ? root.corners[3] : -1
        color: root.fill
        border.width: !root.edge ? 0 : root.edgeWidth >= 0 ? root.edgeWidth : Theme.hairlineWidth
        border.color: root.edgeColor !== "" ? Theme.colour(root.edgeColor) : Theme.hairline

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
