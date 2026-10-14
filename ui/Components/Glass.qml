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
    // Per-corner radii only when given: an explicit -1 squares the corner on Qt 6.11 (every sheet drew square
    // corners); undefined resets the property, so `radius` applies. Radii are held to what the shape can take.
    readonly property real maxRadius: Math.min(width, height) / 2
    function clampR(r: real): real {
        return Math.min(Math.max(0, r), maxRadius);
    }
    // the corners as drawn, [top left, top right, bottom right, bottom left]: what a window's blur region must
    // follow, or the blur shows past a rounded corner as a square frosted patch
    readonly property var drawnCorners: (corners ?? [radius, radius, radius, radius]).map(r => clampR(r))

    // The shadow falls only outside the sheet: a translucent sheet over its own shadow reads darker than
    // the native bar at the same opacity (measured: 47 vs 64 on the same wallpaper), so the sheet's shape
    // is cut out of it.
    readonly property bool shadowed: ExperiencePolicy.shadows && root.raised
    readonly property real shadowBlur: ExperiencePolicy.shadowQuality === "layered" ? 18 : 10
    readonly property real shadowOffset: ExperiencePolicy.shadowQuality === "layered" ? 6 : 3
    // how far the shadow reaches past the sheet: a window must leave this much room around it, or the soft edge is
    // cut off by the window's square bounds (a rectangle with sharp corners around the rounded sheet)
    readonly property int shadowExtent: Math.ceil(shadowBlur + shadowOffset) + 2
    readonly property int shadowReach: shadowed ? shadowExtent : 0
    readonly property int shadowPad: Math.max(24, shadowReach)
    Item {
        id: shadowLayer
        anchors.fill: parent
        anchors.margins: -root.shadowPad
        visible: false
        layer.enabled: root.shadowed
        RectangularShadow {
            anchors.fill: parent
            anchors.margins: root.shadowPad
            // RectangularShadow takes one radius: the roundest drawn corner (the sheet's own shape is cut out of the
            // shadow below, so a squarer corner never shows a gap)
            radius: Math.max(...root.drawnCorners)
            color: Theme.shadow
            blur: root.shadowBlur
            offset: Qt.vector2d(0, root.shadowOffset)
        }
    }
    Item {
        id: shapeLayer
        anchors.fill: shadowLayer
        visible: false
        layer.enabled: root.shadowed
        Rectangle {
            anchors.fill: parent
            anchors.margins: root.shadowPad
            radius: root.clampR(root.radius)
            topLeftRadius: root.corners ? root.clampR(root.corners[0]) : undefined
            topRightRadius: root.corners ? root.clampR(root.corners[1]) : undefined
            bottomRightRadius: root.corners ? root.clampR(root.corners[2]) : undefined
            bottomLeftRadius: root.corners ? root.clampR(root.corners[3]) : undefined
            color: "black"
        }
    }
    MultiEffect {
        anchors.fill: shadowLayer
        visible: root.shadowed
        source: root.shadowed ? shadowLayer : null
        maskEnabled: true
        maskInverted: true
        maskSource: root.shadowed ? shapeLayer : null
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1
    }

    Rectangle {
        id: sheet

        anchors.fill: parent
        radius: root.clampR(root.radius)
        topLeftRadius: root.corners ? root.clampR(root.corners[0]) : undefined
        topRightRadius: root.corners ? root.clampR(root.corners[1]) : undefined
        bottomRightRadius: root.corners ? root.clampR(root.corners[2]) : undefined
        bottomLeftRadius: root.corners ? root.clampR(root.corners[3]) : undefined
        color: root.fill
        border.width: !root.edge ? 0 : root.edgeWidth >= 0 ? root.edgeWidth : Theme.hairlineWidth
        border.color: root.edgeColor !== "" ? Theme.colour(root.edgeColor) : Theme.hairline

        Rectangle {
            visible: root.sheen
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                leftMargin: root.clampR(root.radius)
                rightMargin: root.clampR(root.radius)
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
