import QtQuick
import qs.Common
import qs.Components
import qs.Services

// Zynith itself: the mark (assembled as the page opens), the name and its line, the version, the project's own
// places, and what it is built on and licensed under.
Column {
    spacing: Metrics.s5

    // ── the mark and the name ──
    Item {
        width: parent.width
        height: 168
        LogoReveal {
            id: mark
            width: 140
            height: 140
            anchors.verticalCenter: parent.verticalCenter
        }
        Column {
            anchors.left: mark.right
            anchors.leftMargin: Metrics.s6
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Metrics.s2
            Label {
                role: "micro"
                caps: true
                tone: "accent"
                text: "// " + About.zynithVersion
            }
            Text {
                text: "ZYNITH SHELL"
                color: Theme.ink
                font.family: Type.display
                font.pixelSize: Math.round(34 * Type.scale)
                font.weight: Font.Medium
                font.letterSpacing: 4
            }
            Label {
                width: parent.width
                role: "body"
                tone: "muted"
                wrapMode: Text.WordWrap
                text: "For the pursuit of elegance and freedom."
            }
        }
    }

    // how Zynith shows you: kept in zynith.toml [profile], apart from your account and its sign-in
    Card {
        width: parent.width
        caption: "You"
        Row {
            width: parent.width
            spacing: Metrics.s5
            Avatar {
                anchors.verticalCenter: parent.verticalCenter
                size: 64
            }
            SchemaForm {
                width: parent.width - 64 - Metrics.s5
                schema: [
                    { key: "name", label: "Name Zynith shows", kind: "text", default: "", hint: "Empty: your account's (" + (About.realName || About.user) + ")" },
                    { key: "avatar", label: "Picture", kind: "image", default: "", hint: "Empty: your account's picture" }
                ]
                valueOf: key => Config.profile[key] ?? ""
                isSet: key => (Config.profile[key] ?? "") !== ""
                onChanged: (key, value) => Config.setProfile(key, value)
                onCleared: key => Config.setProfile(key, "")
            }
        }
        Label {
            width: parent.width
            role: "caption"
            tone: "faint"
            wrapMode: Text.WordWrap
            text: "Kept in ~/.config/zynith/zynith.toml under [profile]. It changes only what Zynith shows — not your account, its password or how you sign in."
        }
    }

    Card {
        width: parent.width
        caption: "The project"
        Repeater {
            model: [
                ["Source", "github.com/adhitya-zynastra/Zynith-Shell", "https://github.com/adhitya-zynastra/Zynith-Shell"],
                ["Documentation", "github.com/adhitya-zynastra/Zynith-Shell/docs", "https://github.com/adhitya-zynastra/Zynith-Shell/tree/main/docs"],
                ["License", "GNU GPL v3.0", "https://www.gnu.org/licenses/gpl-3.0.html"]
            ]
            delegate: Item {
                required property var modelData
                width: parent.width
                height: 24
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    role: "caption"
                    tone: "faint"
                    caps: true
                    text: parent.modelData[0]
                }
                Label {
                    id: link
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    role: "label"
                    tone: linkArea.containsMouse ? "accent" : "muted"
                    text: parent.modelData[1] + "  ↗"
                    MouseArea {
                        id: linkArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Qt.openUrlExternally(link.parent.modelData[2])
                    }
                }
            }
        }
    }

    Card {
        width: parent.width
        caption: "This system"

        Repeater {
            model: [["Zynith", About.zynithVersion], ["niri", About.niriVersion], ["Quickshell", About.quickshellVersion], ["Operating system", About.os], ["Kernel", About.kernel]]
            delegate: Item {
                required property var modelData
                width: parent.width
                height: 20
                Label {
                    role: "caption"
                    tone: "faint"
                    caps: true
                    text: parent.modelData[0]
                }
                Label {
                    anchors.right: parent.right
                    role: "label"
                    tone: "muted"
                    text: parent.modelData[1]
                }
            }
        }
    }

    Card {
        width: parent.width
        caption: "Licenses"

        Repeater {
            model: ["Zynith is free software under the GNU GPL v3.0.", "Includes MIT-licensed code; its notice is kept in LICENSES/ and its authors are credited in CREDITS.md.", "UI fonts Inter, Space Grotesk and Sora: SIL Open Font License 1.1.", "Icons: Tabler Icons (MIT).", "Runs on Quickshell (LGPL-3.0 / GPL-3.0) and niri (GPL-3.0)."]
            delegate: Label {
                required property string modelData
                width: parent.width
                role: "label"
                tone: "muted"
                wrapMode: Text.WordWrap
                elide: Text.ElideNone
                text: modelData
            }
        }
    }
}
