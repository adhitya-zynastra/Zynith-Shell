import QtQuick
import qs.Common
import qs.Components
import qs.Services

// The weather the native shell already fetches: now, and the days or hours ahead ([control_panel]
// weather_forecast). Its page adds the details: feels like, humidity, wind, UV, sunrise and sunset.
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

    readonly property var d: Weather.data
    readonly property var now: d.current ?? ({})
    readonly property string unit: d.unit ?? "°"
    property string view: Config.controlPanel?.weather_forecast ?? "daily"

    spacing: Metrics.s4

    Hold {
        service: "weather"
        when: root.active
    }

    // ── not there yet ──
    Label {
        visible: !Weather.valid
        width: root.colW
        role: "label"
        tone: "faint"
        wrapMode: Text.WordWrap
        text: root.d.enabled === false ? "Weather is off — turn it on in the native Settings → Weather" : (root.d.error ?? "") !== "" ? root.d.error : "Fetching the weather…"
    }

    // ── now ──
    Item {
        visible: Weather.valid
        width: root.colW
        height: 64
        Interactive {
            anchors.fill: parent
            anchors.margins: -Metrics.s2
            radius: Metrics.radiusLg
            visible: !root.expanded
            onClicked: PanelRouter.navigate("weather", root.screen.name)
        }
        Icon {
            id: nowGlyph
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            name: Weather.glyph(root.now.code ?? 0, root.now.isDay ?? true)
            size: 40
            tone: "accent"
        }
        Label {
            id: nowTemp
            anchors.left: nowGlyph.right
            anchors.leftMargin: Metrics.s4
            anchors.verticalCenter: parent.verticalCenter
            role: "display2"
            numeric: true
            text: Math.round(root.now.temperature ?? 0) + root.unit
        }
        Column {
            anchors.left: nowTemp.right
            anchors.leftMargin: Metrics.s4
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Label {
                width: parent.width
                role: "body"
                elide: Text.ElideRight
                text: Weather.describe(root.now.code ?? 0)
            }
            Label {
                id: placeLine
                width: parent.width
                role: "caption"
                tone: "faint"
                elide: Text.ElideRight
                // the city alone when the full name ("Lisbon, Portugal") would cut off the feels-like reading
                readonly property string feels: root.now.feelsLike !== undefined ? "  ·  feels " + Math.round(root.now.feelsLike) + "°" : ""
                readonly property string place: root.d.location ?? ""
                text: (fullFits.width <= width ? place : place.split(",")[0]) + feels
                TextMetrics {
                    id: fullFits
                    font: placeLine.font
                    text: placeLine.place + placeLine.feels
                }
            }
        }
    }

    // ── the details (the page) ──
    Grid {
        id: details
        visible: Weather.valid && root.expanded
        width: root.colW
        columns: 3
        rowSpacing: Metrics.s3
        columnSpacing: Metrics.s3
        readonly property real cell: (width - columnSpacing * 2) / 3
        readonly property var today: (root.d.days ?? [])[0] ?? ({})
        Repeater {
            model: [
                { icon: "temperature", label: "Feels like", value: root.now.feelsLike !== undefined ? Math.round(root.now.feelsLike) + root.unit : "—" },
                { icon: "droplet", label: "Humidity", value: (root.now.humidity ?? 0) + "%" },
                { icon: "wind", label: "Wind", value: Math.round(root.now.wind ?? 0) + " km/h " + root.compass(root.now.windDirection ?? 0) },
                { icon: "uv-index", label: "UV index", value: (root.now.uv ?? 0).toFixed(1) },
                { icon: "sunrise", label: "Sunrise", value: (details.today.sunrise ?? "").slice(11, 16) || "—" },
                { icon: "sunset", label: "Sunset", value: (details.today.sunset ?? "").slice(11, 16) || "—" }
            ]
            delegate: Rectangle {
                required property var modelData
                width: details.cell
                height: 58
                radius: Metrics.radiusLg
                color: Theme.well
                Column {
                    anchors.left: parent.left
                    anchors.leftMargin: Metrics.s3
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Row {
                        spacing: Metrics.s2
                        Icon {
                            name: modelData.icon
                            size: 13
                            tone: "faint"
                        }
                        Label {
                            role: "caption"
                            tone: "faint"
                            text: modelData.label
                        }
                    }
                    Label {
                        role: "body"
                        numeric: true
                        text: modelData.value
                    }
                }
            }
        }
    }
    function compass(deg: int): string {
        return ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][Math.round(((deg % 360) + 360) % 360 / 45) % 8];
    }

    // ── ahead: the days, or the hours ──
    Segmented {
        visible: Weather.valid && root.expanded
        width: root.colW
        current: root.view
        options: [{ key: "daily", label: "Days" }, { key: "hourly", label: "Hours" }]
        onPicked: key => {
            root.view = key;
            forecastIn.restart();
        }
    }
    Item {
        id: forecast
        visible: Weather.valid
        width: root.colW
        height: 92
        clip: true

        readonly property var items: root.view === "hourly" ? Weather.upcomingHours(root.expanded ? 24 : 6) : (root.d.days ?? []).slice(0, root.expanded ? 7 : 5)
        readonly property int shown: root.expanded && root.view === "hourly" ? 8 : items.length
        readonly property real cell: width / Math.max(1, Math.min(items.length, shown))

        ParallelAnimation {
            id: forecastIn
            NumberAnimation {
                target: strip
                property: "opacity"
                from: 0
                to: 1
                duration: Motion.spatialFast
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: stripShift
                property: "y"
                from: 10
                to: 0
                duration: Motion.spatialFast
                easing.type: Easing.OutCubic
            }
        }

        Flickable {
            id: strip
            anchors.fill: parent
            contentWidth: row.width
            flickableDirection: Flickable.HorizontalFlick
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentWidth > width
            transform: Translate {
                id: stripShift
            }
            Row {
                id: row
                Repeater {
                    model: forecast.items
                    delegate: Column {
                        required property var modelData
                        required property int index
                        readonly property bool hourly: modelData.time !== undefined
                        width: forecast.cell
                        spacing: Metrics.s2
                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            role: "caption"
                            tone: index === 0 ? "accent" : "faint"
                            caps: true
                            text: parent.hourly ? (index === 0 ? "Now" : modelData.time.slice(11, 16)) : index === 0 ? "Today" : Qt.formatDate(new Date(modelData.date + "T12:00:00"), "ddd")
                        }
                        Icon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            name: Weather.glyph(modelData.code ?? 0, parent.hourly ? modelData.isDay : true)
                            size: 20
                        }
                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            role: "label"
                            numeric: true
                            text: parent.hourly ? Math.round(modelData.temperature) + "°" : Math.round(modelData.max) + "°"
                        }
                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            role: "caption"
                            numeric: true
                            tone: "faint"
                            text: parent.hourly ? (modelData.rain > 0 ? modelData.rain + "%" : " ") : Math.round(modelData.min) + "°"
                        }
                    }
                }
            }
        }
    }
}
