import QtQuick
import qs.Common
import qs.Components
import qs.Services

// A month: today marked, the week starting where you like it, week numbers if wanted. The arrows (or the
// wheel) leave the current month and the title brings you back.
Item {
    id: root
    property var settings: ({})
    readonly property bool interactive: true
    function opt(key: string): var {
        return WidgetTypes.value("calendar", settings, key);
    }
    readonly property color ink: Theme.colour(opt("color"))
    readonly property bool mondayFirst: opt("first_day") !== "sunday"
    readonly property bool weeks: opt("show_week_numbers") === true
    readonly property string family: (settings.font_family ?? "") !== "" ? settings.font_family : Type.ui

    property int shift: 0          // months away from now
    readonly property date today: Time.now
    readonly property date month: new Date(today.getFullYear(), today.getMonth() + shift, 1)
    readonly property int lead: mondayFirst ? (month.getDay() + 6) % 7 : month.getDay()
    readonly property int days: new Date(month.getFullYear(), month.getMonth() + 1, 0).getDate()
    readonly property int rows: Math.ceil((lead + days) / 7)
    function isoWeek(d: date): int {
        const t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
        const n = t.getUTCDay() || 7;
        t.setUTCDate(t.getUTCDate() + 4 - n);
        const y = new Date(Date.UTC(t.getUTCFullYear(), 0, 1));
        return Math.ceil(((t - y) / 86400000 + 1) / 7);
    }

    implicitWidth: 300
    implicitHeight: 300
    readonly property real cell: Math.min(width / (weeks ? 8 : 7), height / (rows + 2))

    WheelHandler {
        onWheel: event => root.shift += event.angleDelta.y > 0 ? -1 : 1
    }

    Item {
        id: head
        width: parent.width
        height: root.cell
        Text {
            anchors.left: parent.left
            anchors.leftMargin: root.weeks ? root.cell : 0
            anchors.verticalCenter: parent.verticalCenter
            text: Qt.formatDate(root.month, "MMMM yyyy")
            font.family: root.family
            font.pixelSize: root.cell * 0.46
            font.weight: Font.Medium
            color: root.ink
            MouseArea {
                anchors.fill: parent
                cursorShape: root.shift !== 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: root.shift = 0
            }
        }
        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            IconButton {
                size: root.cell * 0.9
                iconSize: root.cell * 0.4
                icon: "chevron-left"
                tone: "muted"
                onClicked: root.shift--
            }
            IconButton {
                size: root.cell * 0.9
                iconSize: root.cell * 0.4
                icon: "chevron-right"
                tone: "muted"
                onClicked: root.shift++
            }
        }
    }

    Grid {
        id: grid
        anchors.top: head.bottom
        x: root.weeks ? root.cell : 0
        columns: 7
        // day names
        Repeater {
            model: 7
            delegate: Text {
                required property int index
                width: root.cell
                height: root.cell
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: Qt.locale().dayName(root.mondayFirst ? (index + 1) % 7 : index, Locale.NarrowFormat)
                font.family: root.family
                font.pixelSize: root.cell * 0.3
                font.capitalization: Font.AllUppercase
                color: Theme.alpha(root.ink, 0.5)
            }
        }
        // the days, padded to whole weeks
        Repeater {
            model: root.rows * 7
            delegate: Item {
                id: dayCell
                required property int index
                readonly property int n: index - root.lead + 1
                readonly property bool inMonth: n >= 1 && n <= root.days
                readonly property bool isToday: inMonth && root.shift === 0 && n === root.today.getDate()
                width: root.cell
                height: root.cell
                Rectangle {
                    anchors.centerIn: parent
                    width: root.cell * 0.82
                    height: width
                    radius: width / 2
                    color: Theme.accent
                    visible: dayCell.isToday
                }
                Text {
                    anchors.centerIn: parent
                    text: dayCell.inMonth ? dayCell.n : ""
                    font.family: root.family
                    font.pixelSize: root.cell * 0.38
                    font.weight: dayCell.isToday ? Font.Bold : Font.Normal
                    font.features: Type.tabular
                    color: dayCell.isToday ? Theme.onAccent : root.ink
                }
            }
        }
    }
    // week numbers down the side
    Column {
        visible: root.weeks
        anchors.top: head.bottom
        anchors.topMargin: root.cell
        Repeater {
            model: root.rows
            delegate: Text {
                required property int index
                width: root.cell
                height: root.cell
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: root.isoWeek(new Date(root.month.getFullYear(), root.month.getMonth(), 1 - root.lead + index * 7 + 3))
                font.family: root.family
                font.pixelSize: root.cell * 0.28
                color: Theme.alpha(root.ink, 0.4)
            }
        }
    }
}
