import QtQuick
import QtQuick.Effects
import qs.Common
import qs.Components
import qs.Services
import "../../Common/MaterialModel.js" as MaterialModel
import "../../Common/BarModel.js" as BarModel

// How Zynith feels. First the material every surface is cut from — Glass, Solid or Blur — each shown on the
// wallpaper as the shell will draw it (the same Glass sheet, with the numbers MaterialModel gives that style).
// Then only what belongs to the chosen material, and below, colour, shape and type.
Column {
    id: page
    spacing: Metrics.s5

    readonly property string style: Material.style
    readonly property real strength: style === "blur" ? Material.blurStrength : Material.glassStrength
    // bars that keep an opacity of their own, which wins over the style's strength (Glass and Blur)
    readonly property var ownOpacity: BarModel.list(Config.barState.bars).filter(b => (b.opacity ?? 0) > 0)
    readonly property var ownShown: ownOpacity.filter(b => b.enabled !== false)
    readonly property int ownHidden: ownOpacity.length - ownShown.length

    PanelHeader {
        width: parent.width
        title: "Appearance"
        caption: "How Zynith feels — choose the material that shapes your desktop"
    }

    // ── the three materials ──
    Row {
        width: parent.width
        spacing: Metrics.s3
        Repeater {
            model: [
                { key: "glass", name: "Glass", line: "Clear and tinted. The wallpaper shows through; edges catch the light." },
                { key: "solid", name: "Solid", line: "Opaque and calm. The palette's own surfaces, depth from elevation." },
                { key: "blur", name: "Blur", line: "Frosted. niri softens whatever is behind each surface." }
            ]
            delegate: MaterialCard {
                required property var modelData
                width: (page.width - Metrics.s3 * 2) / 3
                info: modelData
                selected: page.style === modelData.key
            }
        }
    }

    // ── the chosen material's own controls ──
    Card {
        width: parent.width
        caption: page.style === "glass" ? "Glass" : page.style === "blur" ? "Blur" : "Solid"
        Column {
            width: parent.width
            spacing: Metrics.s4

            Column {
                visible: page.style !== "solid"
                width: parent.width
                spacing: Metrics.s2
                Label {
                    role: "label"
                    text: page.style === "blur" ? "Blur strength" : "Glass strength"
                }
                Segmented {
                    width: Math.min(parent.width, 420)
                    options: [{ key: "subtle", label: "Subtle" }, { key: "balanced", label: "Balanced" }, { key: "strong", label: "Strong" }]
                    current: MaterialModel.levelOf(page.strength)
                    onPicked: key => page.style === "blur" ? Material.setBlurStrength(Material.levels[key]) : Material.setGlassStrength(Material.levels[key])
                }
                Label {
                    width: parent.width
                    role: "caption"
                    tone: "faint"
                    wrapMode: Text.WordWrap
                    text: page.style === "blur" ? "How much niri softens what is behind (its blur passes), and how thin the tint over it is. A stronger blur carries more of the legibility." : "From nearly solid with a quiet edge, to clear glass with light along its edges. Text keeps its contrast at every strength."
                }
            }

            Column {
                visible: page.style === "solid"
                width: parent.width
                spacing: Metrics.s2
                SettingSlider {
                    title: "Tint toward the wallpaper"
                    detail: "How far the surfaces lean toward the wallpaper's colour instead of neutral"
                    domain: "appearance"
                    key: "tint"
                }
            }

            // said plainly when something is set aside, or overridden
            Label {
                visible: Material.pausedText !== ""
                width: parent.width
                role: "caption"
                tone: "accent"
                wrapMode: Text.WordWrap
                text: Material.pausedText + (Material.paused.includes("blur") ? ". It comes back by itself; Settings → Performance can keep it." : "")
            }
            Row {
                visible: page.style !== "solid" && page.ownShown.length > 0
                width: parent.width
                spacing: Metrics.s3
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - follow.width - Metrics.s3
                    role: "caption"
                    tone: "muted"
                    wrapMode: Text.WordWrap
                    text: page.ownShown.map(b => b.name).join(", ") + (page.ownShown.length === 1 ? " keeps its own opacity" : " keep their own opacity") + ", so the strength does not change " + (page.ownShown.length === 1 ? "it" : "them") + " or the panels opened from " + (page.ownShown.length === 1 ? "it" : "them") + "." + (page.ownHidden > 0 ? " So do " + page.ownHidden + " hidden " + (page.ownHidden === 1 ? "bar" : "bars") + "; the button covers them too." : "")
                }
                Chip {
                    id: follow
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "check"
                    text: "Let them follow the style"
                    onClicked: {
                        let s = BarEdits.state;
                        for (const b of page.ownOpacity)
                            s = BarModel.setKey(s, b.id, "opacity", undefined);
                        BarEdits.commit(s, "Let bars follow the surface style");
                    }
                }
            }

            // fine control, apart
            Column {
                visible: Config.settingsAdvanced && page.style !== "solid"
                width: parent.width
                spacing: Metrics.s2
                Label {
                    role: "micro"
                    caps: true
                    tone: "faint"
                    text: "Advanced · exact strength"
                }
                Item {
                    width: parent.width
                    height: 24
                    Slider {
                        id: fine
                        width: parent.width - 120 - Metrics.s3
                        anchors.verticalCenter: parent.verticalCenter
                        value: page.strength
                        step: 0.01
                        onCommitted: v => page.style === "blur" ? Material.setBlurStrength(v) : Material.setGlassStrength(v)
                    }
                    Label {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 120
                        horizontalAlignment: Text.AlignRight
                        role: "label"
                        numeric: true
                        tone: "muted"
                        text: Math.round(fine.displayed * 100) + (page.style === "blur" ? "  ·  niri " + MaterialModel.resolve("blur", 0.5, fine.displayed, { blurAvailable: true }).nativeBlurStrength : "")
                    }
                }
            }
        }
    }

    Card {
        width: parent.width
        caption: "Colour"
        SettingChoice {
            title: "Accent"
            detail: "The one highlight colour"
            domain: "appearance"
            key: "accent"
            options: [{ key: "wallpaper", label: "Wallpaper" }, { key: "#b4c5ff", label: "Blue" }, { key: "#e2bbdb", label: "Rose" }, { key: "#c5d6a8", label: "Sage" }]
        }
        SettingSlider {
            visible: page.style !== "solid"
            title: "Tint toward the wallpaper"
            detail: "How far the surfaces lean toward the wallpaper's colour instead of neutral"
            domain: "appearance"
            key: "tint"
        }
        SettingChoice {
            title: "Contrast"
            domain: "appearance"
            key: "contrast"
            options: [{ key: "standard", label: "Standard" }, { key: "high", label: "High" }]
        }
    }

    Card {
        width: parent.width
        caption: "Shape and edges"
        SettingChoice {
            title: "Edges"
            detail: "The line around every surface"
            domain: "appearance"
            key: "border"
            options: [{ key: "none", label: "None" }, { key: "subtle", label: "Subtle" }, { key: "defined", label: "Defined" }]
        }
        SettingSlider {
            title: "Roundness"
            detail: "Every corner of every surface, together"
            domain: "appearance"
            key: "radius"
            from: 0.5
            to: 1.5
            format: v => "× " + v.toFixed(2)
        }
    }

    Card {
        width: parent.width
        caption: "Type"
        SettingFont {
            title: "Interface font"
            detail: "Labels, menus and reading text"
            domain: "appearance"
            key: "font_ui"
            fallback: "Inter (Zynith's)"
        }
        SettingFont {
            title: "Display font"
            detail: "Clocks and numbers (headings are set in Sora)"
            domain: "appearance"
            key: "font_display"
            fallback: "Space Grotesk (Zynith's)"
        }
        SettingFont {
            title: "Monospace font"
            detail: "Values, units and the data voice"
            domain: "appearance"
            key: "font_mono"
            fallback: "JetBrains Mono"
        }
        SettingSlider {
            title: "Text size"
            domain: "appearance"
            key: "font_scale"
            from: 0.85
            to: 1.3
            format: v => "× " + v.toFixed(2)
        }
    }

    // One material on the wallpaper: a bar and a panel cut from it with the numbers this style resolves to (the
    // same Glass sheet the shell draws), the name and a line under it. Blur is shown with a blur of the wallpaper
    // inside the panel's shape — the compositor's own cannot be drawn into a preview, so this is its likeness.
    component MaterialCard: Item {
        id: card
        property var info
        property bool selected
        readonly property var m: MaterialModel.resolve(info.key, info.key === Material.style ? Material.glassStrength : 0.5, info.key === Material.style ? Material.blurStrength : 0.5, { blurAvailable: true })
        readonly property color tone: info.key === "solid" ? Theme.mix(Theme.surfaceLow, Theme.surfaceMid, 0.55) : Theme.mix(Theme.base, Theme.surfaceLow, 0.5)
        readonly property color edge: Theme.alpha(Theme.mix(Theme.pal("outline_variant"), "#ffffff", info.key === "solid" ? 0 : 0.25), Math.min(0.85, m.edgeAlpha * 2.6))
        implicitHeight: scene.height + Metrics.s3 + text.implicitHeight

        Rectangle {
            id: scene
            width: parent.width
            height: Math.round(width * 0.62)
            radius: Metrics.radiusLg
            color: Theme.base
            clip: true
            border.width: card.selected ? 2 : 1
            border.color: card.selected ? Theme.accent : Theme.rule
            Behavior on border.color {
                ColorAnim {}
            }

            Image {
                id: wall
                anchors.fill: parent
                anchors.margins: 1
                source: Scheme.image !== "" ? "file://" + Scheme.image : ""
                // one small decode, shared by the three cards (same source and size)
                sourceSize.width: 480
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
            }
            // the bar
            Glass {
                x: parent.width * 0.08
                y: parent.height * 0.08
                width: parent.width * 0.84
                height: Math.max(14, parent.height * 0.12)
                radius: height / 2
                fill: Theme.alpha(card.tone, card.m.fillAlpha)
                edgeColor: card.edge.toString()
                sheenOverride: card.m.sheenAlpha
                depthOverride: card.m.shadows ? card.m.shadowDepth : 0
                raised: true
                Label {
                    anchors.centerIn: parent
                    role: "micro"
                    numeric: true
                    text: Qt.formatTime(Time.now, "hh:mm")
                }
            }
            // the panel (blur: the wallpaper softened inside its shape, under the same sheet)
            Item {
                id: panelArea
                x: parent.width * 0.16
                y: parent.height * 0.30
                width: parent.width * 0.68
                height: parent.height * 0.58
                visible: card.info.key === "blur"
                layer.enabled: visible
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: panelMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1
                }
                MultiEffect {
                    x: -panelArea.x + 1
                    y: -panelArea.y + 1
                    width: wall.width
                    height: wall.height
                    source: wall
                    blurEnabled: true
                    blurMax: 48
                    blur: 0.35 + 0.65 * (card.info.key === Material.style ? Material.blurStrength : 0.5)
                }
            }
            Item {
                id: panelMask
                x: panelArea.x
                y: panelArea.y
                width: panelArea.width
                height: panelArea.height
                visible: false
                layer.enabled: card.info.key === "blur"
                Rectangle {
                    anchors.fill: parent
                    radius: Metrics.radiusMd
                    color: "black"
                }
            }
            Glass {
                x: panelArea.x
                y: panelArea.y
                width: panelArea.width
                height: panelArea.height
                radius: Metrics.radiusMd
                fill: Theme.alpha(card.tone, card.m.fillAlpha)
                edgeColor: card.edge.toString()
                sheenOverride: card.m.sheenAlpha
                depthOverride: card.m.shadows ? card.m.shadowDepth : 0
                raised: true
                Column {
                    x: Metrics.s3
                    y: Metrics.s3
                    width: parent.width - Metrics.s3 * 2
                    spacing: 4
                    Label {
                        role: "label"
                        text: "Now playing"
                    }
                    Rectangle {
                        width: parent.width
                        height: 4
                        radius: 2
                        color: Theme.alpha(Theme.ink, 0.25)
                        Rectangle {
                            width: parent.width * 0.6
                            height: parent.height
                            radius: 2
                            color: Theme.accent
                        }
                    }
                    Label {
                        role: "micro"
                        tone: "muted"
                        text: "Wi‑Fi  ·  Bluetooth  ·  28°"
                    }
                }
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: Material.setStyle(card.info.key)
            }
        }
        Column {
            id: text
            anchors.top: scene.bottom
            anchors.topMargin: Metrics.s3
            width: parent.width
            spacing: 2
            Label {
                role: "micro"
                caps: true
                tone: card.selected ? "accent" : "faint"
                text: (card.selected ? "// " : "") + card.info.name
            }
            Label {
                width: parent.width
                role: "caption"
                tone: "muted"
                wrapMode: Text.WordWrap
                text: card.info.line
            }
        }
    }
}
