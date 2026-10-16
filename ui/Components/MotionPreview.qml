import QtQuick
import qs.Common

// The desktop's motion in miniature, made with the same tokens the shell uses (Motion's durations and curves at
// the current speed and feel): a bar, a panel unfolding from it, its rows arriving, a dial opening. It plays when
// it appears, whenever the speed or the feel changes, and on a click; otherwise it rests, so a Settings page
// left open spends nothing. With motion reduced it shows the end state at once, as the shell does.
Item {
    id: root

    implicitHeight: 132

    // 0 → 1: the panel's unfold; the rows and the dial follow on their own clocks
    property real unfold: 0
    property bool lit: false

    function play(): void {
        run.stop();
        root.unfold = 0;
        root.lit = false;
        if (Motion.reduced) {
            root.unfold = 1;
            root.lit = true;
            return;
        }
        run.start();
    }
    Component.onCompleted: Qt.callLater(play)
    Connections {
        target: Motion
        function onSpeedChanged(): void {
            again.restart();
        }
        function onStyleChanged(): void {
            again.restart();
        }
    }
    // a slider dragged replays once it rests, not on every step
    Timer {
        id: again
        interval: 250
        onTriggered: root.play()
    }

    SequentialAnimation {
        id: run
        PauseAnimation {
            duration: 120
        }
        NumberAnimation {
            target: root
            property: "unfold"
            to: 1
            duration: Motion.enter
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.spatialFastCurve
        }
        PropertyAction {
            target: root
            property: "lit"
            value: true
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Metrics.radiusMd
        color: Theme.alpha(Theme.base, 0.35)
        border.width: 1
        border.color: Theme.alpha(Theme.ink, 0.06)
    }

    // the bar
    Rectangle {
        id: bar
        x: Metrics.s4
        y: Metrics.s3
        width: parent.width - Metrics.s4 * 2
        height: 14
        radius: 7
        color: Theme.alpha(Theme.ink, 0.10)
        Rectangle {
            x: parent.width - 34
            anchors.verticalCenter: parent.verticalCenter
            width: 22
            height: 2
            radius: 1
            color: Theme.accent
            opacity: root.unfold > 0 ? 1 : 0.3
        }
    }

    // the panel, unfolding from under the bar's right end
    Item {
        id: card
        x: parent.width - Metrics.s4 - width
        y: bar.y + bar.height + 3
        width: Math.min(260, parent.width * 0.6)
        height: (parent.height - y - Metrics.s3) * root.unfold
        clip: true
        Rectangle {
            width: parent.width
            height: root.height - card.y - Metrics.s3
            radius: Metrics.radiusMd
            color: Theme.mix(Theme.surfaceHigh, Theme.base, 0.25)
            border.width: 1
            border.color: Theme.alpha(Theme.ink, 0.08)

            // rows arriving one after another
            Column {
                x: Metrics.s3
                y: Metrics.s3
                spacing: 6
                Repeater {
                    model: 4
                    delegate: Rectangle {
                        id: line
                        required property int index
                        readonly property real arrive: Math.max(0, Math.min(1, (root.unfold - 0.25 - index * 0.12) / 0.4))
                        width: (card.width - Metrics.s3 * 2 - 48) * (index === 0 ? 0.8 : 1 - index * 0.15)
                        height: 8
                        radius: 4
                        color: Theme.alpha(Theme.ink, index === 0 ? 0.28 : 0.14)
                        opacity: arrive
                        transform: Translate {
                            y: (1 - line.arrive) * -6
                        }
                    }
                }
            }
            // a dial opening once the panel is in
            ApertureDial {
                anchors.right: parent.right
                anchors.rightMargin: Metrics.s3
                anchors.top: parent.top
                anchors.topMargin: Metrics.s3
                size: 40
                glyph: "wifi"
                lit: root.lit
                reading: ({ value: 0.75, segments: 4 })
            }
        }
    }

    Label {
        x: Metrics.s4
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Metrics.s3
        role: "caption"
        tone: "faint"
        text: Motion.reduced ? "Motion is reduced: things change at once" : "Click to play again"
    }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.play()
    }
}
