import QtQuick
import qs.Common
import qs.Services

// What can be done about a notification from where it is shown: an inline reply for senders that take one
// (messengers), and the sender's own actions. Shared by the popups and the notification centre. Both need the
// sender still running (entry.n): a notification restored from an earlier session can be read and cleared, not
// answered.
Column {
    id: root

    required property var entry
    // the sender's buttons (the reply field shows regardless)
    property bool showActions: true
    readonly property bool typing: replyField.activeFocus
    readonly property bool live: !!entry?.n
    readonly property var actions: live ? entry.actions.filter(a => a.id !== "default" && a.text !== "") : []
    readonly property bool canReply: live && (entry.reply ?? "") !== ""
    readonly property bool hasAny: canReply || (showActions && actions.length > 0 && (Config.notifications.showActions ?? true))

    spacing: Metrics.s2
    visible: hasAny

    function focusReply(): void {
        replyField.forceActiveFocus();
    }
    function send(): void {
        if (replyField.text.trim() === "")
            return;
        Notifications.reply(root.entry.key, replyField.text);
        replyField.text = "";
    }

    Rectangle {
        visible: root.canReply
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
            anchors.right: sendButton.left
            anchors.rightMargin: Metrics.s2
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.ink
            font.family: Type.ui
            font.pixelSize: Type.label
            clip: true
            Keys.onReturnPressed: root.send()
            Keys.onEnterPressed: root.send()
            Keys.onEscapePressed: focus = false
            Label {
                visible: replyField.text === ""
                anchors.verticalCenter: parent.verticalCenter
                role: "label"
                tone: "faint"
                text: root.entry?.reply ?? ""
            }
        }
        IconButton {
            id: sendButton
            anchors.right: parent.right
            anchors.rightMargin: 3
            anchors.verticalCenter: parent.verticalCenter
            size: 26
            iconSize: 13
            icon: "corner-down-left"
            tone: "accent"
            enabled: replyField.text.trim() !== ""
            onClicked: root.send()
        }
    }

    Flow {
        visible: root.showActions && actionsRepeater.count > 0 && (Config.notifications.showActions ?? true)
        width: parent.width
        spacing: Metrics.s2

        Repeater {
            id: actionsRepeater
            model: root.actions

            delegate: Item {
                required property var modelData
                required property int index
                // the first action is the one meant: it carries the signal; the rest stay quiet
                readonly property bool primary: index === 0
                width: actionLabel.implicitWidth + Metrics.s5 * 2
                height: 28

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: actionArea.pressed ? Theme.press : parent.primary ? Theme.signalFill : actionArea.containsMouse ? Theme.hover : "transparent"
                    border.width: Metrics.hairline
                    border.color: parent.primary ? Theme.signalEdge : actionArea.containsMouse ? Theme.hairline : Theme.rule
                }
                Label {
                    id: actionLabel
                    anchors.centerIn: parent
                    role: "label"
                    font.weight: parent.primary ? Font.Medium : Font.Normal
                    tone: parent.primary ? "accent" : "ink"
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
