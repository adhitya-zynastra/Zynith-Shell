import QtQuick
import QtQuick.Effects
import Quickshell.Services.Notifications
import qs.Common
import qs.Services
import "../Common/NotificationGroups.js" as Groups

// One notification in the notification centre, laid out as a phone's shade lays it out: the app (its icon and
// name) and how long ago over the title and the text, the sender's picture at the side, and — opened — the whole
// text with its actions and reply. A tap opens what it is about; a sideways swipe, the × or the middle button
// clears it. `entry` is a Notifications history entry.
Item {
    id: root

    required property var entry
    property bool expanded: false
    // the keyboard is on this card
    property bool selected: false
    // arrived while the centre was open
    property bool fresh: false
    // the app line (a card under its app's header leaves it out)
    property bool showApp: true
    property real now: Date.now()

    signal toggled
    signal opened
    signal dismissed

    readonly property bool critical: entry.urgency === NotificationUrgency.Critical
    readonly property bool hovered: hover.hovered
    readonly property bool typing: actionsBox.typing
    // there is more to see opened: text beyond two lines, or something to do
    readonly property bool expandable: bodyText.truncated || bodyText.lineCount > 2 || actionsBox.actions.length > 0 || actionsBox.canReply
    readonly property string icon: Notifications.iconFor(entry)
    // a picture the sender attached (a contact, an album), shown at the side; an icon name is the app's own
    readonly property string picture: Notifications.pictureFor(entry)

    implicitHeight: column.implicitHeight + Metrics.s4 * 2
    height: implicitHeight

    function focusReply(): void {
        actionsBox.focusReply();
    }

    // the swipe: the card follows the pointer sideways; far or fast enough clears it
    property real dragX: 0
    DragHandler {
        id: swipe
        target: null
        xAxis.enabled: true
        yAxis.enabled: false
        grabPermissions: PointerHandler.CanTakeOverFromAnything
        onTranslationChanged: root.dragX = translation.x
        onActiveChanged: if (!active) {
            const far = Math.abs(root.dragX) > root.width * 0.35 || Math.abs(centroid.velocity.x) > 900;
            if (far) {
                flingOut.to = root.dragX > 0 ? root.width * 1.2 : -root.width * 1.2;
                flingOut.start();
            } else {
                settleBack.start();
            }
        }
    }
    NumberAnimation {
        id: flingOut
        target: root
        property: "dragX"
        duration: Motion.exit
        easing.type: Easing.InCubic
        onFinished: root.dismissed()
    }
    NumberAnimation {
        id: settleBack
        target: root
        property: "dragX"
        to: 0
        duration: Motion.spatialFast
        easing.type: Easing.OutCubic
    }

    HoverHandler {
        id: hover
    }

    Item {
        id: face
        width: parent.width
        height: parent.height
        x: root.dragX
        opacity: 1 - Math.min(0.75, Math.abs(root.dragX) / root.width)

        Rectangle {
            anchors.fill: parent
            radius: Metrics.radiusLg
            color: tap.pressed ? Theme.press : root.hovered ? Theme.mix(Theme.plate, Theme.hover, 0.5) : Theme.plate
            border.width: root.selected ? 1.5 : root.fresh ? 1 : 0
            border.color: root.selected ? Theme.focus : Theme.accentLine
            Behavior on color {
                ColorAnim {}
            }
        }
        // critical carries a danger edge, nothing louder
        Rectangle {
            visible: root.critical
            x: 1
            anchors.verticalCenter: parent.verticalCenter
            width: 3
            height: parent.height * 0.5
            radius: 2
            color: Theme.danger
        }

        TapHandler {
            id: tap
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
            gesturePolicy: TapHandler.ReleaseWithinBounds
            onTapped: (point, button) => {
                if (button === Qt.MiddleButton)
                    root.dismissed();
                else
                    root.opened();
            }
        }

        // the age (when there is no app line), the new mark, clear and open up
        Row {
            id: controls
            z: 1
            anchors.right: parent.right
            anchors.rightMargin: Metrics.s3
            y: Metrics.s4 - 3
            height: 24
            spacing: Metrics.s1
            Label {
                visible: !root.showApp
                anchors.verticalCenter: parent.verticalCenter
                role: "caption"
                tone: "muted"
                text: Groups.ago(root.entry.time, root.now)
            }
            Rectangle {
                visible: root.fresh
                anchors.verticalCenter: parent.verticalCenter
                width: 6
                height: 6
                radius: 3
                color: Theme.accent
            }
            // clear it (shown on hover, or with the keyboard on it)
            IconButton {
                anchors.verticalCenter: parent.verticalCenter
                size: 22
                iconSize: 12
                icon: "x"
                tone: "muted"
                opacity: root.hovered || root.selected ? 1 : 0
                visible: opacity > 0
                Behavior on opacity {
                    NumberAnimation {
                        duration: Motion.focus
                    }
                }
                onClicked: root.dismissed()
            }
            IconButton {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.expandable || root.expanded
                size: 22
                iconSize: 12
                icon: "chevron-down"
                tone: "muted"
                rotation: root.expanded ? 180 : 0
                Behavior on rotation {
                    Anim {
                        role: "spatialFast"
                    }
                }
                onClicked: root.toggled()
            }
        }

        Column {
            id: column
            x: Metrics.s4
            y: Metrics.s4
            width: parent.width - Metrics.s4 * 2
            spacing: Metrics.s1

            // the app and how long ago (under its app's header the age sits with the controls instead)
            Item {
                visible: root.showApp
                width: parent.width
                height: 18

                Item {
                    id: badge
                    width: 16
                    height: 16
                    anchors.verticalCenter: parent.verticalCenter
                    Image {
                        id: appIcon
                        anchors.fill: parent
                        sourceSize.width: 32
                        sourceSize.height: 32
                        asynchronous: true
                        source: root.icon
                    }
                    // no icon to be had: the app's initial on a tinted disc
                    Rectangle {
                        visible: appIcon.status !== Image.Ready
                        anchors.fill: parent
                        radius: width / 2
                        color: Theme.accentSoft
                        Label {
                            anchors.centerIn: parent
                            role: "micro"
                            tone: "accent"
                            font.weight: Font.Medium
                            text: (root.entry.appName || "?").charAt(0).toUpperCase()
                        }
                    }
                }
                Label {
                    id: appLabel
                    anchors.left: badge.right
                    anchors.leftMargin: Metrics.s2
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, parent.width - controls.width - Metrics.s5 - badge.width)
                    elide: Text.ElideRight
                    role: "caption"
                    tone: "muted"
                    text: (root.entry.appName || "Notification") + "  ·  " + Groups.ago(root.entry.time, root.now)
                }
            }

            // the title and the text, the sender's picture beside them
            Item {
                width: parent.width
                // under its app's header the age and controls float at the top right: the picture sits below them
                readonly property real pictureTop: root.showApp ? 0 : 22
                height: Math.max(texts.implicitHeight, root.picture !== "" ? 44 + pictureTop : 0)

                Column {
                    id: texts
                    width: parent.width - (root.picture !== "" ? 44 + Metrics.s3 : 0)
                    spacing: 2
                    Label {
                        width: parent.width - (root.showApp ? 0 : controls.width + Metrics.s2)
                        role: "body"
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                        wrapMode: root.expanded ? Text.Wrap : Text.NoWrap
                        maximumLineCount: root.expanded ? 3 : 1
                        text: root.entry.summary || root.entry.appName || "Notification"
                    }
                    Label {
                        id: bodyText
                        visible: text !== ""
                        width: parent.width
                        role: "label"
                        tone: "muted"
                        wrapMode: Text.Wrap
                        elide: Text.ElideRight
                        maximumLineCount: root.expanded ? 12 : 2
                        textFormat: Text.PlainText
                        text: root.entry.body ?? ""
                    }
                }
                // the sender's picture, rounded like the card
                Item {
                    visible: root.picture !== "" && senderPicture.status === Image.Ready
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.topMargin: parent.pictureTop
                    width: 44
                    height: 44
                    Image {
                        id: senderPicture
                        anchors.fill: parent
                        visible: false
                        sourceSize.width: 88
                        sourceSize.height: 88
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        source: root.picture
                    }
                    Rectangle {
                        id: pictureShape
                        anchors.fill: parent
                        radius: Metrics.radiusMd
                        visible: false
                        layer.enabled: parent.visible
                    }
                    MultiEffect {
                        anchors.fill: parent
                        source: senderPicture
                        maskEnabled: true
                        maskSource: pictureShape
                        maskThresholdMin: 0.5
                        maskSpreadAtMin: 1
                    }
                }
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

            // opened: what can be done about it
            NotificationActions {
                id: actionsBox
                width: parent.width
                topPadding: Metrics.s2
                entry: root.entry
                showActions: true
                visible: root.expanded && hasAny
            }
        }
    }
}
