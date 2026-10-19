import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
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
    property bool sheen: Material.sheenAlpha > 0
    // a preview of another material (Appearance) sets these; left undefined, the current material's apply
    property var depthOverride: undefined
    // how much of the shadow shows (a surface still forming — a panel's water drop — keeps it at 0, then settles in)
    property real shadowOpacity: 1
    property var sheenOverride: undefined
    // a change of fill glides (a material or palette change); a surface whose fill follows its motion every frame
    // (MaterialSettle's frost) turns this off while it does, or the glide trails the motion
    property bool easeFill: true
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
    readonly property bool shadowWanted: (depthOverride !== undefined ? depthOverride > 0 : Material.shadows) && root.raised
    // Paused or resumed (Power Saver, a style change), the shadow fades rather than popping, and the layers (and the
    // room a window leaves for the shadow, shadowReach) stay until it has faded out: a window that shrank the moment
    // shadows paused cut the fading shadow off square.
    property real shadowLevel: shadowWanted ? 1 : 0
    Behavior on shadowLevel {
        NumberAnimation {
            duration: Motion.effects
        }
    }
    readonly property bool shadowed: shadowLevel > 0
    // depth is the material's (Solid sits highest, Glass a little lower; Blur floats on its blur instead)
    readonly property real shadowBlur: 10 + 8 * (depthOverride ?? Material.shadowDepth)
    readonly property real shadowOffset: 3 + 3 * (depthOverride ?? Material.shadowDepth)
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
        visible: root.shadowed && root.shadowOpacity > 0
        opacity: root.shadowOpacity * root.shadowLevel
        source: root.shadowed ? shadowLayer : null
        maskEnabled: true
        maskInverted: true
        maskSource: root.shadowed ? shapeLayer : null
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1
    }

    // ── the backdrop's stand-in, in motion ──
    // Glass's resting backdrop is the wallpaper (niri's xray, blurred). A moving surface has no compositor backdrop
    // (MaterialSettle), so what showed through instead was the window really behind it: over a dark window, a dark
    // tint on every opening that lifted as the surface settled (the launcher's centre 36 → 48). Moving, the sheet
    // carries the wallpaper itself, softened and lined up with the screen, so it reads the same as at rest.
    //   standIn: draw it now · still: the wallpaper image · screenX/Y: this item's top left on its screen
    property bool standIn: false
    property string still: ""
    property real screenX: 0
    property real screenY: 0
    property size screenSize: Qt.size(1920, 1080)
    Loader {
        anchors.fill: parent
        // kept while there is a still (decoded once, cached), shown only in motion
        active: root.still !== ""
        visible: root.standIn
        sourceComponent: Item {
            // the wallpaper small (an eighth of the screen's width), drawn cropped to the screen as the desktop draws
            // it; bilinear upscaling softens it like the backdrop's blur
            Image {
                id: wall
                visible: false
                source: root.still
                sourceSize.width: Math.ceil(root.screenSize.width / 8)
                asynchronous: true
                smooth: true
            }
            // texture pixel q lands on the screen at q × k + off (PreserveAspectCrop), so in this item at that − screenX/Y
            readonly property real k: wall.implicitWidth > 0 ? Math.max(root.screenSize.width / wall.implicitWidth, root.screenSize.height / wall.implicitHeight) : 1
            readonly property real offX: (root.screenSize.width - wall.implicitWidth * k) / 2
            readonly property real offY: (root.screenSize.height - wall.implicitHeight * k) / 2
            Shape {
                anchors.fill: parent
                visible: wall.status === Image.Ready
                ShapePath {
                    strokeWidth: 0
                    strokeColor: "transparent"
                    fillItem: wall
                    fillTransform: PlanarTransform.fromAffineMatrix(parent.parent.k, 0, 0, parent.parent.k, parent.parent.offX - root.screenX, parent.parent.offY - root.screenY)
                    PathRectangle {
                        width: root.width
                        height: root.height
                        topLeftRadius: root.drawnCorners[0]
                        topRightRadius: root.drawnCorners[1]
                        bottomRightRadius: root.drawnCorners[2]
                        bottomLeftRadius: root.drawnCorners[3]
                    }
                }
            }
        }
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
        // a change of material (or palette) glides instead of snapping; an interrupted one restarts from where it is
        Behavior on color {
            enabled: root.easeFill
            ColorAnim {}
        }
        Behavior on border.color {
            ColorAnim {}
        }

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
                    color: root.sheenOverride !== undefined ? Theme.alpha("#ffffff", root.sheenOverride) : Theme.sheen
                }
                GradientStop {
                    position: 1
                    color: "transparent"
                }
            }
        }
    }
}
