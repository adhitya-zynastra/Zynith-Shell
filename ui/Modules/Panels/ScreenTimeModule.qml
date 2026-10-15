import QtQuick
import Quickshell
import qs.Common
import qs.Components
import qs.Services

// Screen time as the native shell counts it: the total, the apps that took it, and when — by the hour today,
// by the day over a range ([control_panel] screen_time_range; the page switches between them).
Flow {
    id: root
    // On its page the module flows into columns — top to bottom, wrapping at a height that balances them
    // ([control_panel] page_columns); in the Control Panel it is one stack, as before.
    readonly property int pageColumns: expanded ? Math.max(1, Config.controlPanel?.page_columns ?? 2) : 1
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

    readonly property int range: Config.controlPanel?.screen_time_range ?? 1
    Component.onCompleted: ScreenTime.setDays(range)
    onRangeChanged: ScreenTime.setDays(range)

    Hold {
        service: "screen_time"
        when: root.active
    }

    readonly property var apps: ScreenTime.apps.slice(0, expanded ? 12 : 3)
    readonly property real longest: ScreenTime.apps.length > 0 ? ScreenTime.apps[0].seconds : 1

    function iconFor(key: string): string {
        const entry = DesktopEntries.heuristicLookup(key);
        return Quickshell.iconPath(entry?.icon ?? key, true);
    }

    spacing: Metrics.s3

    Label {
        visible: !ScreenTime.enabled
        width: root.colW
        role: "label"
        tone: "faint"
        wrapMode: Text.WordWrap
        text: "Screen time is off — turn it on in the native Settings → Shell"
    }

    // ── the total ──
    Item {
        visible: ScreenTime.enabled
        width: root.colW
        height: 44
        Interactive {
            anchors.fill: parent
            anchors.margins: -Metrics.s2
            radius: Metrics.radiusLg
            visible: !root.expanded
            onClicked: PanelRouter.navigate("screen-time", root.screen.name)
        }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            Label {
                role: "caption"
                tone: "faint"
                caps: true
                text: ScreenTime.days === 1 ? "Screen time today" : "Last " + ScreenTime.days + " days"
            }
            Label {
                role: "title"
                numeric: true
                text: ScreenTime.format(ScreenTime.total) + (ScreenTime.days > 1 ? "  ·  " + ScreenTime.format(ScreenTime.total / ScreenTime.days) + " a day" : "")
            }
        }
        Icon {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.expanded
            name: "chevron-right"
            size: 14
            tone: "faint"
        }
    }

    // ── the range (the page) ──
    Segmented {
        visible: ScreenTime.enabled && root.expanded
        width: root.colW
        current: String(ScreenTime.days)
        options: [{ key: "1", label: "Today" }, { key: "3", label: "3 days" }, { key: "14", label: "14 days" }]
        onPicked: key => ScreenTime.setDays(Number(key))
    }

    // ── when: hours or days ──
    Item {
        id: chart
        visible: ScreenTime.enabled && (root.expanded || ScreenTime.buckets.length > 0)
        width: root.colW
        height: root.expanded ? 120 : 56
        readonly property var values: ScreenTime.buckets
        readonly property real peak: Math.max(1, ...values)
        readonly property real slot: width / Math.max(1, values.length)
        readonly property int nowIndex: ScreenTime.hourly ? Time.now.getHours() : values.length - 1

        Repeater {
            model: chart.values
            delegate: Item {
                required property var modelData
                required property int index
                x: index * chart.slot
                width: chart.slot
                height: chart.height - (root.expanded ? 16 : 0)
                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.max(2, parent.width - (chart.values.length > 14 ? 2 : 6))
                    radius: Math.min(4, width / 2)
                    height: Math.max(2, parent.height * (modelData / chart.peak) * chart.grow)
                    color: index === chart.nowIndex ? Theme.accent : Theme.alpha(Theme.accent, 0.38)
                }
            }
        }
        // the axis: a few hours, or each day
        Repeater {
            model: root.expanded ? (ScreenTime.hourly ? [0, 6, 12, 18] : ScreenTime.labels.map((l, i) => i).filter(i => ScreenTime.labels.length <= 7 || i % 2 === 0)) : []
            delegate: Label {
                required property int modelData
                x: modelData * chart.slot + (chart.slot - width) / 2
                anchors.bottom: parent.bottom
                role: "micro"
                tone: "faint"
                text: ScreenTime.hourly ? String(modelData).padStart(2, "0") : (ScreenTime.labels[modelData] ?? "")
            }
        }
        // bars rise when the numbers arrive
        property real grow: 1
        NumberAnimation {
            id: growAnim
            target: chart
            property: "grow"
            from: 0
            to: 1
            duration: Motion.spatial
            easing.type: Motion.enterEasing
        }
        onValuesChanged: growAnim.restart()
    }

    // ── who ──
    Repeater {
        model: ScreenTime.enabled ? root.apps : []
        delegate: Item {
            id: app
            required property var modelData
            readonly property string icon: root.iconFor(modelData.key)
            width: root.colW
            height: 36
            Item {
                id: appIcon
                width: 24
                height: 24
                anchors.verticalCenter: parent.verticalCenter
                Image {
                    anchors.fill: parent
                    visible: app.icon !== ""
                    sourceSize.width: 48
                    sourceSize.height: 48
                    source: app.icon
                }
                Icon {
                    anchors.centerIn: parent
                    visible: app.icon === ""
                    name: "app-window"
                    tone: "muted"
                }
            }
            Column {
                anchors.left: appIcon.right
                anchors.leftMargin: Metrics.s3
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3
                Item {
                    width: parent.width
                    height: appName.implicitHeight
                    Label {
                        id: appName
                        width: parent.width - 60
                        role: "label"
                        elide: Text.ElideRight
                        text: app.modelData.name || app.modelData.key
                    }
                    Label {
                        anchors.right: parent.right
                        role: "caption"
                        numeric: true
                        tone: "muted"
                        text: ScreenTime.format(app.modelData.seconds)
                    }
                }
                Rectangle {
                    width: parent.width * (app.modelData.seconds / root.longest) * chart.grow
                    height: 3
                    radius: 2
                    color: Theme.alpha(Theme.accent, 0.6)
                }
            }
        }
    }
}
