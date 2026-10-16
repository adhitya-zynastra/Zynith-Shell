import QtQuick
import Zynith.Native
import qs.Common
import qs.Components
import qs.Services

// The month, and what is coming up in the calendars the native shell syncs (calendar-events). Week numbers,
// the first day of the week and the events list are [control_panel] calendar_week_numbers, week_start and
// calendar_events. A wheel or the arrows turn the month; the title goes back to today.
Flow {
    id: root
    // On its page the module flows into columns — top to bottom, wrapping at a height that balances them
    // ([control_panel] page_columns); in the Control Panel it is one stack, as before.
    readonly property int pageColumns: expanded ? Metrics.pageColumns(width, Config.controlPanel?.page_columns ?? 2) : 1
    readonly property real colW: pageColumns > 1 ? (width - spacing * (pageColumns - 1)) / pageColumns : width
    flow: pageColumns > 1 ? Flow.TopToBottom : Flow.LeftToRight
    height: pageColumns > 1 ? balancedHeight() : implicitHeight
    function columnsFor(h: real): int {
        let cols = 1, used = 0;
        for (const c of children) {
            if (!c.visible || c.height <= 0)
                continue;
            const need = (used > 0 ? used + spacing : 0) + c.height;
            if (need > h && used > 0) {
                cols++;
                used = c.height;
            } else {
                used = need;
            }
        }
        return cols;
    }
    function balancedHeight(): real {
        let total = 0, tallest = 0, n = 0;
        for (const c of children) {
            if (!c.visible || c.height <= 0)
                continue;
            total += c.height;
            tallest = Math.max(tallest, c.height);
            n++;
        }
        total += spacing * Math.max(0, n - 1);
        let h = Math.max(tallest, total / pageColumns);
        for (let i = 0; i < 60 && columnsFor(h) > pageColumns; i++)
            h += 12;
        return Math.ceil(h);
    }

    property var screen: null
    property bool active: true
    property bool expanded: false

    readonly property var cfg: Config.controlPanel ?? ({})
    readonly property bool weekNumbers: cfg.calendar_week_numbers === true
    readonly property bool showEvents: cfg.calendar_events !== false
    readonly property int firstDay: cfg.week_start === "sunday" ? 0 : 1

    // the month shown: its first day
    property date month: new Date(Time.now.getFullYear(), Time.now.getMonth(), 1)
    readonly property date today: Time.now
    function step(by: int): void {
        month = new Date(month.getFullYear(), month.getMonth() + by, 1);
        slideFrom = by * 28;
        turn.restart();
    }
    function goToday(): void {
        const now = new Date(today.getFullYear(), today.getMonth(), 1);
        const by = Math.sign((now - month) || 0);
        month = now;
        if (by !== 0) {
            slideFrom = by * 28;
            turn.restart();
        }
    }

    // the 42 days the grid shows, from the week the month starts in
    readonly property var days: {
        const first = new Date(month.getFullYear(), month.getMonth(), 1);
        const lead = (first.getDay() - firstDay + 7) % 7;
        const out = [];
        for (let i = 0; i < 42; i++)
            out.push(new Date(month.getFullYear(), month.getMonth(), 1 - lead + i));
        return out;
    }
    function key(d: date): string {
        return d.getFullYear() + "-" + d.getMonth() + "-" + d.getDate();
    }
    function sameDay(a: date, b: date): bool {
        return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
    }
    // ISO 8601 week of the year
    function isoWeek(d: date): int {
        const t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
        const day = t.getUTCDay() || 7;
        t.setUTCDate(t.getUTCDate() + 4 - day);
        const yearStart = new Date(Date.UTC(t.getUTCFullYear(), 0, 1));
        return Math.ceil(((t - yearStart) / 86400000 + 1) / 7);
    }

    // ── events ──
    property var events: []
    property bool synced: false
    readonly property var eventDays: {
        const set = {};
        for (const e of events) {
            const d = new Date(e.start * 1000);
            set[key(d)] = e.color || "";
        }
        return set;
    }
    function readEvents(): void {
        if (!showEvents)
            return;
        CoreClient.call("calendar-events 42", text => {
            try {
                const d = JSON.parse(text);
                root.synced = d.enabled === true;
                root.events = d.events ?? [];
            } catch (e) {}
        });
    }
    onActiveChanged: if (active)
        readEvents()
    Component.onCompleted: readEvents()

    spacing: Metrics.s3

    // ── the month and the way through it ──
    Item {
        width: root.colW
        height: 30
        Label {
            id: title
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            role: "title"
            text: Qt.formatDate(root.month, "MMMM yyyy")
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.goToday()
            }
        }
        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            IconButton {
                icon: "calendar-event"
                tone: "muted"
                visible: !root.sameDay(root.month, new Date(root.today.getFullYear(), root.today.getMonth(), 1))
                onClicked: root.goToday()
            }
            IconButton {
                icon: "chevron-left"
                tone: "muted"
                onClicked: root.step(-1)
            }
            IconButton {
                icon: "chevron-right"
                tone: "muted"
                onClicked: root.step(1)
            }
            IconButton {
                visible: !root.expanded
                icon: "arrows-diagonal"
                tone: "faint"
                onClicked: PanelRouter.navigate("calendar", root.screen.name)
            }
        }
    }

    // ── the grid ──
    property real slideFrom: 0
    Item {
        id: gridBox
        width: root.colW
        height: weekdays.height + Metrics.s1 + grid.height
        clip: true

        readonly property real gutter: root.weekNumbers ? 26 : 0
        readonly property real cell: (width - gutter) / 7

        WheelHandler {
            onWheel: e => root.step(e.angleDelta.y > 0 ? -1 : 1)
        }

        Row {
            id: weekdays
            x: gridBox.gutter
            Repeater {
                model: 7
                delegate: Label {
                    required property int index
                    width: gridBox.cell
                    horizontalAlignment: Text.AlignHCenter
                    role: "caption"
                    tone: "faint"
                    caps: true
                    text: Qt.locale().dayName((index + root.firstDay) % 7, Locale.NarrowFormat)
                }
            }
        }

        Item {
            id: grid
            y: weekdays.height + Metrics.s1
            width: parent.width
            height: Math.min(gridBox.cell, root.expanded ? 46 : 38) * 6
            readonly property real rowH: height / 6
            transform: Translate {
                id: slide
            }

            ParallelAnimation {
                id: turn
                NumberAnimation {
                    target: slide
                    property: "x"
                    from: root.slideFrom
                    to: 0
                    duration: Motion.spatialFast
                    easing.type: Motion.enterEasing
                }
                NumberAnimation {
                    target: grid
                    property: "opacity"
                    from: 0.2
                    to: 1
                    duration: Motion.spatialFast
                    easing.type: Motion.enterEasing
                }
            }

            // week numbers
            Repeater {
                model: root.weekNumbers ? 6 : 0
                delegate: Label {
                    required property int index
                    x: 0
                    y: index * grid.rowH
                    width: gridBox.gutter
                    height: grid.rowH
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: Text.AlignHCenter
                    role: "micro"
                    numeric: true
                    tone: "faint"
                    text: root.isoWeek(root.days[index * 7 + (root.firstDay === 0 ? 1 : 0)])
                }
            }

            Repeater {
                model: root.days
                delegate: Item {
                    id: day
                    required property var modelData
                    required property int index
                    readonly property bool inMonth: modelData.getMonth() === root.month.getMonth()
                    readonly property bool isToday: root.sameDay(modelData, root.today)
                    readonly property var dot: root.eventDays[root.key(modelData)]
                    x: gridBox.gutter + (index % 7) * gridBox.cell
                    y: Math.floor(index / 7) * grid.rowH
                    width: gridBox.cell
                    height: grid.rowH

                    Rectangle {
                        anchors.centerIn: parent
                        width: Math.min(34, Math.min(parent.width, parent.height) - 4)
                        height: width
                        radius: width / 2
                        color: day.isToday ? Theme.accent : dayArea.containsMouse ? Theme.hover : "transparent"
                        Behavior on color {
                            ColorAnim {}
                        }
                    }
                    Label {
                        anchors.centerIn: parent
                        role: "label"
                        numeric: true
                        color: day.isToday ? Theme.onAccent : day.inMonth ? Theme.ink : Theme.inkFaint
                        font.weight: day.isToday ? Font.DemiBold : Font.Normal
                        text: day.modelData.getDate()
                    }
                    Rectangle {
                        visible: day.dot !== undefined
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 2
                        width: 4
                        height: 4
                        radius: 2
                        color: day.dot ? day.dot : Theme.accent
                    }
                    MouseArea {
                        id: dayArea
                        anchors.fill: parent
                        hoverEnabled: true
                    }
                }
            }
        }
    }

    // ── what is coming up ──
    Column {
        visible: root.showEvents && (root.expanded || root.events.length > 0)
        width: root.colW
        spacing: Metrics.s1

        Label {
            role: "caption"
            tone: "faint"
            caps: true
            text: "Coming up"
        }
        Label {
            visible: root.events.length === 0
            width: parent.width
            role: "label"
            tone: "faint"
            wrapMode: Text.WordWrap
            text: root.synced ? "Nothing in the next six weeks" : "No calendar is connected — add one in the native Settings → Calendar"
        }
        Repeater {
            model: root.events.slice(0, root.expanded ? 20 : 3)
            delegate: Item {
                id: ev
                required property var modelData
                readonly property date start: new Date(modelData.start * 1000)
                readonly property date end: new Date(modelData.end * 1000)
                width: root.colW
                height: 40
                Rectangle {
                    id: bar
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 3
                    height: 28
                    radius: 2
                    color: ev.modelData.color || Theme.accent
                }
                Column {
                    anchors.left: bar.right
                    anchors.leftMargin: Metrics.s3
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    Label {
                        width: parent.width
                        role: "label"
                        elide: Text.ElideRight
                        text: ev.modelData.title || "Untitled"
                    }
                    Label {
                        width: parent.width
                        role: "caption"
                        tone: "faint"
                        elide: Text.ElideRight
                        text: (root.sameDay(ev.start, root.today) ? "Today" : Qt.formatDate(ev.start, "ddd d MMM")) + (ev.modelData.all_day ? " · all day" : " · " + Qt.formatTime(ev.start, "HH:mm") + "–" + Qt.formatTime(ev.end, "HH:mm")) + (ev.modelData.location ? " · " + ev.modelData.location : "")
                    }
                }
                Interactive {
                    anchors.fill: parent
                    visible: (ev.modelData.url ?? "") !== ""
                    radius: Metrics.radiusMd
                    onClicked: Qt.openUrlExternally(ev.modelData.url)
                }
            }
        }
    }
}
