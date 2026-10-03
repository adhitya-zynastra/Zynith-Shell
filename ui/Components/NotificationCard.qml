import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import qs.Common
import qs.Services

// One notification: who sent it, what it says, what can be done about it. Used by the popups and the
// history panel; `entry` is a Notifications history entry.
Item {
    id: root

    required property var entry
    property bool compact: false
    // as a popup, × closes the popup (the history keeps it); in the history it removes the entry
    property bool popup: false
    readonly property bool critical: entry.urgency === NotificationUrgency.Critical
    readonly property bool hovered: hover.hovered
    readonly property bool typing: replyField.activeFocus
    signal activated

    // An icon name becomes an image://icon URL even when the theme lacks it, which draws Qt's
    // missing-image checkerboard; only names the theme really has are used.
    function iconSource(name: string): string {
        if (name === "")
            return "";
        if (name.startsWith("/"))
            return "file://" + name;
        if (name.startsWith("file://"))
            return name;
        return Quickshell.iconPath(name, true);
    }
    readonly property string picture: {
        const image = entry.image ?? "";
        if (image.startsWith("image://icon/"))
            return iconSource(image.substring(13).split("?")[0]);
        return image !== "" ? image : iconSource(entry.appIcon ?? "");
    }

    implicitWidth: 360
    implicitHeight: body.implicitHeight + Metrics.s4 * 2

    HoverHandler {
        id: hover
    }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onClicked: mouse => {
            if (mouse.button === Qt.MiddleButton) {
                Notifications.dismiss(root.entry.key);
                return;
            }
            const def = root.entry.actions.find(a => a.id === "default");
            if (def)
                Notifications.invoke(root.entry.key, "default");
            root.activated();
        }
    }

    // critical carries an accent edge, nothing louder
    Rectangle {
        visible: root.critical
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: 2
        height: parent.height * 0.42
        radius: 1
        color: Theme.danger
    }

    Row {
        id: body
        x: Metrics.s4
        y: Metrics.s4
        width: parent.width - Metrics.s4 * 2
        spacing: Metrics.s4

        Item {
            id: badge
            width: 36
            height: 36

            Rectangle {
                anchors.fill: parent
                radius: Metrics.radiusPlate
                color: Theme.plate
                visible: picture.status !== Image.Ready
            }
            Image {
                id: picture
                anchors.fill: parent
                sourceSize.width: 72
                sourceSize.height: 72
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                source: root.picture
                layer.enabled: root.entry.image !== ""
            }
            Text {
                visible: picture.status !== Image.Ready
                anchors.centerIn: parent
                font.family: Type.icons
                font.pixelSize: 18
                color: Theme.inkMuted
                text: Icons.glyph("bell")
            }
        }

        Column {
            width: parent.width - badge.width - parent.spacing
            spacing: 2

            Item {
                width: parent.width
                height: app.implicitHeight

                Label {
                    id: app
                    width: parent.width - when.implicitWidth - close.width - Metrics.s3
                    role: "data"
                    tone: "faint"
                    text: (Config.notifications.showAppName ?? true) ? (root.entry.appName || "Notification") : ""
                }
                Label {
                    id: when
                    anchors.right: close.left
                    anchors.rightMargin: Metrics.s2
                    role: "data"
                    tone: "faint"
                    text: Qt.formatTime(new Date(root.entry.time), "HH:mm")
                }
                Text {
                    id: close
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 14
                    opacity: root.hovered ? 1 : 0
                    font.family: Type.icons
                    font.pixelSize: 13
                    color: closeArea.containsMouse ? Theme.ink : Theme.inkFaint
                    text: Icons.glyph("x")

                    Behavior on opacity {
                        NumberAnimation {
                            duration: Motion.focus
                        }
                    }
                    MouseArea {
                        id: closeArea
                        anchors.fill: parent
                        anchors.margins: -6
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.popup ? Notifications.close(root.entry.key) : Notifications.dismiss(root.entry.key)
                    }
                }
            }
            Label {
                width: parent.width
                role: "body"
                font.weight: Font.Medium
                text: root.entry.summary
            }
            Label {
                visible: text !== ""
                width: parent.width
                role: "label"
                tone: "muted"
                wrapMode: Text.Wrap
                elide: Text.ElideRight
                maximumLineCount: root.compact ? 2 : 4
                textFormat: Text.PlainText
                text: root.entry.body
            }

            // progress, when the sender reports one (the "value" hint)
            Item {
                visible: (root.entry.progress ?? -1) >= 0
                width: parent.width
                height: 14
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - pct.width - Metrics.s3
                    height: 3
                    radius: 2
                    color: Theme.rule
                    Rectangle {
                        width: parent.width * Math.max(0, Math.min(1, (root.entry.progress ?? 0) / 100))
                        height: parent.height
                        radius: 2
                        color: Theme.alpha(Theme.ink, 0.78)
                        Behavior on width {
                            Anim {
                                role: "spatialFast"
                            }
                        }
                    }
                }
                Label {
                    id: pct
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    role: "caption"
                    numeric: true
                    tone: "muted"
                    text: Math.round(root.entry.progress ?? 0) + "%"
                }
            }

            // a reply, for senders that take one (messengers)
            Rectangle {
                visible: (root.entry.reply ?? "") !== "" && root.entry.n
                width: parent.width
                height: 32
                radius: 16
                color: Theme.well
                border.width: Metrics.hairline
                border.color: replyField.activeFocus ? Theme.accentLine : Theme.hairline
                TextInput {
                    id: replyField
                    anchors.left: parent.left
                    anchors.leftMargin: Metrics.s4
                    anchors.right: send.left
                    anchors.rightMargin: Metrics.s2
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.ink
                    font.family: Type.ui
                    font.pixelSize: Type.label
                    clip: true
                    Keys.onReturnPressed: {
                        Notifications.reply(root.entry.key, text);
                        text = "";
                    }
                    Keys.onEscapePressed: focus = false
                    Label {
                        visible: replyField.text === ""
                        anchors.verticalCenter: parent.verticalCenter
                        role: "label"
                        tone: "faint"
                        text: root.entry.reply ?? ""
                    }
                }
                IconButton {
                    id: send
                    anchors.right: parent.right
                    anchors.rightMargin: 3
                    anchors.verticalCenter: parent.verticalCenter
                    size: 26
                    iconSize: 13
                    icon: "corner-down-left"
                    tone: "accent"
                    enabled: replyField.text.trim() !== ""
                    onClicked: Notifications.reply(root.entry.key, replyField.text)
                }
            }

            Flow {
                visible: !root.compact && actionsRepeater.count > 0 && (Config.notifications.showActions ?? true)
                width: parent.width
                spacing: Metrics.s2
                topPadding: Metrics.s2

                Repeater {
                    id: actionsRepeater
                    model: root.entry.n ? root.entry.actions.filter(a => a.id !== "default" && a.text !== "") : []

                    delegate: Item {
                        required property var modelData
                        width: actionLabel.implicitWidth + Metrics.s5 * 2
                        height: 28

                        Rectangle {
                            anchors.fill: parent
                            radius: height / 2
                            color: actionArea.pressed ? Theme.press : actionArea.containsMouse ? Theme.accentSoft : Theme.hover
                        }
                        Label {
                            id: actionLabel
                            anchors.centerIn: parent
                            role: "label"
                            text: parent.modelData.text
                        }
                        MouseArea {
                            id: actionArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Notifications.invoke(root.entry.key, parent.modelData.id)
                        }
                    }
                }
            }
        }
    }
}
