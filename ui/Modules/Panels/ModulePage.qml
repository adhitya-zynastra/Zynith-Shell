import QtQuick
import Zynith.Native
import qs.Common
import qs.Components
import qs.Services

// A Control Panel module on a page of its own (the native Control Center's tabs): audio, power, monitor,
// calendar, weather, screen-time. The same module, expanded; back returns to where it was opened from.
Column {
    id: root

    property string kind: ""
    property var screen: null
    property real visibleProgress: 1
    property bool canGoBack: false
    property bool active: true
    // opened by itself (its own bar icon) rather than among the Control Panel's tabs: its own, compact width
    property bool alone: false
    // on the connected sheet: how far in the sheet stands, and whether the strip above carries this page's head
    property real sheetInset: 0
    property bool headInStrip: false
    readonly property string stripCaption: page?.caption ?? ""
    signal back

    // a page among the Control Panel's tabs is as wide as the dashboard (tab_page_width; 0 = the dashboard's),
    // so switching tabs only changes the height, and its module lays out in columns
    readonly property var cfg: Config.controlPanel ?? ({})
    readonly property bool tabbed: !alone && (cfg.tab_bar ?? true) && Array.from(cfg.tabs ?? ["control", "media", "audio", "power", "weather", "calendar"]).includes(kind)
    readonly property int preferredWidth: tabbed ? ((cfg.tab_page_width ?? 0) > 0 ? cfg.tab_page_width : (cfg.dashboard_width ?? 1080)) : Math.max(cfg.width ?? 420, 460)
    readonly property var pages: ({
            media: { title: "Now playing", caption: Media.app, component: mediaPage },
            audio: { title: "Sound", caption: "Devices and apps", component: audio },
            power: { title: "Power", caption: "Profiles and battery", component: power },
            monitor: { title: "Displays", caption: "Brightness and colour", component: monitor },
            calendar: { title: "Calendar", caption: Qt.formatDate(Time.now, "dddd d MMMM"), component: calendar },
            weather: { title: "Weather", caption: Weather.data.location ?? "", component: weather },
            "screen-time": { title: "Screen time", caption: "Where the hours went", component: screenTime }
        })
    readonly property var page: pages[kind] ?? null

    // the page's heading on the Control Panel's hero (title, one line of detail, its one live readout)
    function clock(s: real): string {
        s = Math.max(0, Math.round(s));
        const h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60);
        return h > 0 ? h + "h " + String(m).padStart(2, "0") + "m" : m + " min";
    }
    function mmss(s: real): string {
        s = Math.max(0, Math.floor(s));
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
    }
    readonly property var heading: {
        switch (kind) {
        case "media":
            return Media.present ? { title: Media.title, detail: [Media.artist, Media.app].filter(s => s).join("  ·  "), value: Media.length > 0 ? mmss(Media.position) : "", unit: Media.length > 0 ? "/ " + mmss(Media.length) : "", caption: Media.playing ? "Playing" : "Paused" } : { title: "Nothing playing", detail: "Music or video from any app that shares it shows up here" };
        case "audio":
            return { title: Audio.ready ? Audio.sinkName : "No output", detail: Audio.micReady ? (Audio.micMuted ? "Microphone muted" : "Microphone live  ·  " + Math.round(Audio.micVolume * 100) + "%") : "No microphone", value: Audio.ready ? (Audio.muted ? "Muted" : String(Math.round(Audio.volume * 100))) : "", unit: Audio.ready && !Audio.muted ? "%" : "", caption: "Output" };
        case "power": {
            const left = Power.present ? (Power.charging ? Power.device?.timeToFull ?? 0 : Power.device?.timeToEmpty ?? 0) : 0;
            return { title: ControlShortcuts.profileLabels[ControlShortcuts.profile] ?? "Power", detail: !Power.present ? "On mains power" : Power.charging ? (left > 0 ? clock(left) + " to full" : "Charging") : (left > 0 ? clock(left) + " left" : "On battery"), value: Power.present ? String(Math.round(Power.level * 100)) : "", unit: Power.present ? "%" : "", caption: Power.present ? (Power.charging ? "Charging" : "Battery") : "" };
        }
        case "monitor":
            return { title: "Displays", detail: "Brightness and colour", value: Backlight.available ? String(Math.round(Backlight.value * 100)) : "", unit: Backlight.available ? "%" : "", caption: Backlight.available ? "Brightness" : "" };
        case "calendar":
            return { title: Qt.formatDate(Time.now, "dddd"), detail: Qt.formatDate(Time.now, "d MMMM yyyy"), value: Qt.formatDate(Time.now, "dd"), unit: "", caption: Qt.formatDate(Time.now, "MMMM") };
        case "weather": {
            const now = Weather.data.current ?? {};
            return Weather.valid ? { title: Weather.describe(now.code ?? 0), detail: [Weather.data.location ?? "", now.feelsLike !== undefined ? "feels " + Math.round(now.feelsLike) + "°" : ""].filter(s => s).join("  ·  "), value: String(Math.round(now.temperature ?? 0)), unit: Weather.data.unit ?? "°", caption: "Now" } : { title: "Weather", detail: "Waiting for the forecast" };
        }
        case "screen-time":
            return { title: "Screen time", detail: "Where the hours went", value: ScreenTime.total > 0 ? clock(ScreenTime.total) : "", unit: "", caption: "Today" };
        }
        return { title: page?.title ?? "", detail: page?.caption ?? "" };
    }
    // the hero carries the heading (PanelContent sets this when it shows one over the page)
    property bool headInHero: false

    // the sheet has no inset at its top (the current tab joins it there)
    padding: sheetInset + (headInStrip ? Metrics.s5 : Metrics.s6 - sheetInset)
    topPadding: headInStrip ? Metrics.s5 : Metrics.s6
    spacing: Metrics.s5
    readonly property real inner: width - padding * 2

    PanelHeader {
        visible: !root.headInStrip && !root.headInHero
        width: root.inner
        title: root.page?.title ?? ""
        caption: root.page?.caption ?? ""
        canGoBack: root.canGoBack
        onBack: root.back()
        IconButton {
            icon: "settings"
            tone: "faint"
            onClicked: {
                PanelRouter.close(root.screen.name);
                Actions.run("settings-open control");
            }
        }
    }

    Loader {
        width: root.inner
        sourceComponent: root.page?.component ?? null
        opacity: Math.max(0, Math.min(1, root.visibleProgress * 1.4 - 0.4))
        transform: Translate {
            y: (1 - root.visibleProgress) * 14
        }
    }

    Component {
        id: mediaPage
        MediaModule {
            screen: root.screen
            active: root.active
            expanded: true
            headed: root.headInHero
        }
    }
    Component {
        id: audio
        AudioModule {
            screen: root.screen
            active: root.active
            expanded: true
        }
    }
    Component {
        id: power
        PowerModule {
            screen: root.screen
            active: root.active
            expanded: true
        }
    }
    Component {
        id: monitor
        MonitorModule {
            screen: root.screen
            active: root.active
            expanded: true
        }
    }
    Component {
        id: calendar
        CalendarModule {
            screen: root.screen
            active: root.active
            expanded: true
        }
    }
    Component {
        id: weather
        WeatherModule {
            screen: root.screen
            active: root.active
            expanded: true
            headed: root.headInHero
        }
    }
    Component {
        id: screenTime
        ScreenTimeModule {
            screen: root.screen
            active: root.active
            expanded: true
        }
    }
}
