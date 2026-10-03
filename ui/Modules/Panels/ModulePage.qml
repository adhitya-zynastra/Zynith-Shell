import QtQuick
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
    signal back

    // a page among the Control Panel's tabs is as wide as the dashboard (tab_page_width; 0 = the dashboard's),
    // so switching tabs only changes the height, and its module lays out in columns
    readonly property var cfg: Config.controlPanel ?? ({})
    readonly property bool tabbed: (cfg.tab_bar ?? true) && Array.from(cfg.tabs ?? ["control", "media", "audio", "power", "weather", "calendar"]).includes(kind)
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

    padding: Metrics.s6
    spacing: Metrics.s5
    readonly property real inner: width - padding * 2

    PanelHeader {
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
