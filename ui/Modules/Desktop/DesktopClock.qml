import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Components
import qs.Services
import "../../Common/Strftime.js" as Strftime

// The time: digital text fitted to its box (format, face, weight, even digits), or an analog dial whose hands
// sweep on the spatial curve. A time zone other than the local one shifts it by that zone's offset.
Item {
    id: root
    property var settings: ({})
    function opt(key: string): var {
        return WidgetTypes.value("clock", settings, key);
    }
    readonly property bool analog: opt("clock_style") === "analog"
    readonly property color ink: Theme.colour(opt("color"))

    // another zone's offset, asked for once per zone
    property int offsetMinutes: 0
    property bool zoned: false
    readonly property string zone: opt("timezone") ?? ""
    onZoneChanged: {
        zoned = zone !== "";
        if (zoned)
            tz.running = true;
    }
    Component.onCompleted: {
        zoned = zone !== "";
        if (zoned)
            tz.running = true;
        if (analog)
            Time.retainSeconds();
    }
    Component.onDestruction: if (analog)
        Time.releaseSeconds()
    onAnalogChanged: analog ? Time.retainSeconds() : Time.releaseSeconds()
    Process {
        id: tz
        command: ["sh", "-c", "TZ=\"$1\" date +%z", "zynith-tz", root.zone]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = text.trim().match(/^([+-])(\d\d)(\d\d)$/);
                root.offsetMinutes = m ? (m[1] === "-" ? -1 : 1) * (parseInt(m[2]) * 60 + parseInt(m[3])) : 0;
            }
        }
    }
    readonly property date time: zoned ? new Date(Time.now.getTime() + (offsetMinutes + Time.now.getTimezoneOffset()) * 60000) : Time.now

    layer.enabled: opt("shadow") === true
    layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: Theme.shadow
        shadowBlur: 0.7
        shadowVerticalOffset: 3
    }

    Text {
        visible: !root.analog
        anchors.fill: parent
        text: Qt.formatDateTime(root.time, Strftime.toQt(root.opt("format") ?? "%H:%M"))
        font.family: {
            const face = root.opt("face");
            if (face === "display")
                return Type.display;
            if (face === "interface")
                return Type.ui;
            const f = root.settings.font_family ?? "";
            return f !== "" ? f : Type.display;
        }
        font.weight: ({ light: Font.Light, regular: Font.Normal, bold: Font.Bold })[root.opt("weight")] ?? Font.Normal
        font.features: root.opt("tabular") ? Type.tabular : ({})
        font.pixelSize: Math.max(8, height * 0.92)
        fontSizeMode: Text.Fit
        minimumPixelSize: 6
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        color: root.ink
    }

    // the dial, built only for an analog clock: a digital one still carried three hidden hands, which swept every
    // second whenever anything asked for seconds and re-rendered the whole desktop window for each sweep
    Loader {
        anchors.centerIn: parent
        width: Math.min(parent.width, parent.height)
        height: width
        active: root.analog
        sourceComponent: dialComponent
    }
    Component {
        id: dialComponent
        Item {
            id: dial
            anchors.fill: parent
            readonly property real r: width / 2

            Rectangle {
                visible: root.opt("circle") !== false
                anchors.fill: parent
                radius: width / 2
                color: Theme.alpha(Theme.base, 0.35)
                border.width: Math.max(1, dial.r * 0.02)
                border.color: Theme.alpha(root.ink, 0.35)
            }
            Repeater {
                model: 12
                delegate: Rectangle {
                    required property int index
                    readonly property bool major: index % 3 === 0
                    width: Math.max(1.5, dial.r * (major ? 0.035 : 0.02))
                    height: dial.r * (major ? 0.14 : 0.08)
                    radius: width / 2
                    color: Theme.alpha(root.ink, major ? 0.9 : 0.5)
                    x: dial.r - width / 2
                    y: dial.r * 0.06
                    transform: Rotation {
                        origin.x: width / 2
                        origin.y: dial.r - dial.r * 0.06
                        angle: index * 30
                    }
                }
            }
            component Hand: Rectangle {
                id: hand
                property real angle: 0
                property real length: 0.6
                property real thickness: 0.04
                width: Math.max(1.5, dial.r * thickness)
                height: dial.r * length
                radius: width / 2
                x: dial.r - width / 2
                y: dial.r - height
                transform: Rotation {
                    origin.x: hand.width / 2
                    origin.y: hand.height
                    angle: hand.angle
                    Behavior on angle {
                        enabled: !Motion.reduced
                        // unwrap at the top of the dial so the hand never spins back the long way
                        NumberAnimation {
                            duration: Motion.spatialFast
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Motion.spatialFastCurve
                        }
                    }
                }
            }
            // angles grow without wrapping, so 59 -> 0 is one step forward
            readonly property real minutesTotal: root.time.getHours() * 60 + root.time.getMinutes()
            Hand {
                angle: dial.minutesTotal * 0.5
                length: 0.5
                thickness: 0.06
                color: root.ink
            }
            Hand {
                angle: dial.minutesTotal * 6
                length: 0.74
                thickness: 0.04
                color: root.ink
            }
            Hand {
                angle: (dial.minutesTotal * 60 + root.time.getSeconds()) * 6
                length: 0.82
                thickness: 0.018
                color: Theme.accent
            }
            Rectangle {
                anchors.centerIn: parent
                width: dial.r * 0.08
                height: width
                radius: width / 2
                color: Theme.accent
            }
        }
    }
}
