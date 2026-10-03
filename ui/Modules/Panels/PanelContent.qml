import QtQuick
import qs.Common
import qs.Components
import qs.Services

// Picks the panel by id and cross-fades when navigating within one surface. New panels register here.
Item {
    id: root

    property string panelId: ""
    property var screen: null
    property real visibleProgress: 1
    property var history: []
    property bool active: true
    // what the panel was opened for, e.g. a launcher mode
    property string context: ""
    property int showings: 0
    // opened by resting the pointer on a bar icon: a quick look, without the hero
    property bool peek: false

    // the panel shown (the incoming one, from the moment it starts coming in)
    property string shownId: panelId

    // [control_panel] tab_bar / tabs: the Control Panel and its pages under one row of tabs (Caelestia's
    // dashboard); a tab switches the page in place
    readonly property var cfg: Config.controlPanel ?? ({})
    readonly property var tabNames: ({
            control: { label: "Dashboard", icon: "layout-dashboard" },
            audio: { label: "Sound", icon: "volume" },
            media: { label: "Media", icon: "music" },
            power: { label: "Power", icon: "bolt" },
            monitor: { label: "Display", icon: "device-desktop" },
            calendar: { label: "Calendar", icon: "calendar" },
            weather: { label: "Weather", icon: "cloud" },
            "screen-time": { label: "Screen time", icon: "hourglass" },
            system: { label: "System", icon: "cpu" },
            network: { label: "Network", icon: "wifi" },
            bluetooth: { label: "Bluetooth", icon: "bluetooth" },
            notifications: { label: "Notifications", icon: "bell" }
        })
    readonly property var tabs: (cfg.tab_bar ?? true) ? Array.from(cfg.tabs ?? ["control", "media", "audio", "power", "weather", "calendar"]).map(t => String(t) === "home" ? "control" : String(t)).filter(t => panels[t] !== undefined).map(t => ({
                    id: t,
                    label: (cfg.tab_labels ?? {})[t] ?? tabNames[t]?.label ?? t,
                    icon: (cfg.tab_icons ?? {})[t] ?? tabNames[t]?.icon ?? ""
                })) : []
    readonly property string tabId: shownId === "home" || shownId === "quick" ? "control" : shownId
    readonly property bool tabbed: tabs.length > 1 && tabs.some(t => t.id === tabId)

    // the hero over the Control Panel (and its tabs, with hero_pages = all)
    readonly property bool heroShown: (cfg.hero ?? true) && (!peek || (cfg.hero_on_peek ?? false)) && (tabId === "control" || (tabbed && (cfg.hero_pages ?? "all") === "all"))
    readonly property real contentTop: (heroShown ? hero.height : 0) + (tabbed ? tabStrip.height : 0)
    implicitHeight: contentTop + (live.item?.implicitHeight ?? 0)
    // a panel may ask for its own width (0: the configured one)
    readonly property int preferredWidth: live.item?.preferredWidth ?? 0
    // where a centred panel's top sits, as a fraction of the screen height
    readonly property real preferredTop: live.item?.preferredTop ?? 0.22
    // a panel that covers the screen and draws its own surfaces; blurItem is the one the compositor blurs
    readonly property bool bare: live.item?.bare ?? false
    readonly property Item blurItem: live.item?.blurItem ?? null
    // a bare panel's say over the dimmed desktop: a colour to lean it towards, and how dim (0..1)
    readonly property var backdropTint: live.item?.backdropTint
    readonly property real backdropDim: live.item?.backdropDim ?? 1

    readonly property var panels: ({
            home: control,
            media: mediaPage,
            system: system,
            network: network,
            bluetooth: bluetooth,
            launcher: launcher,
            clipboard: clipboard,
            notifications: notifications,
            quick: control,
            wallpaper: wallpaper,
            control: control,
            session: session,
            audio: audioPage,
            power: powerPage,
            monitor: monitorPage,
            calendar: calendarPage,
            weather: weatherPage,
            "screen-time": screenTimePage
        })

    // Two slots: the panel shown and the one coming in. A change cross-fades them — the old one shrinks a
    // little and fades, the new one grows into place — while the card glides to its new size (Caelestia's
    // popouts). [panels] switch = none swaps at once; content_scale is how far they shrink (1 = not at all).
    readonly property string switchStyle: Config.panels?.switch ?? "morph"
    readonly property real contentScale: Math.max(0.5, Math.min(1, Config.panels?.content_scale ?? 0.94))
    property int front: 0
    readonly property Loader live: front === 0 ? slotA : slotB
    readonly property Loader leaving: front === 0 ? slotB : slotA
    property string idA: ""
    property string idB: ""
    Component.onCompleted: if (idA === "" && idB === "")
        idA = panelId

    onPanelIdChanged: {
        if ((front === 0 ? idA : idB) === panelId)
            return;
        shownId = panelId;
        // nothing shown yet, or not on screen: no cross-fade
        if (switchStyle === "none" || Motion.contentOut === 0 || (idA === "" && idB === "") || visibleProgress < 0.99) {
            swap.stop();
            if (front === 0) {
                idA = panelId;
                idB = "";
            } else {
                idB = panelId;
                idA = "";
            }
            live.opacity = 1;
            live.scale = 1;
            if (front === 0)
                idA = panelId;
            else
                idB = panelId;
            return;
        }
        // the incoming panel takes the free slot and becomes the live one at once (the card sizes to it)
        swap.stop();
        if (front === 0)
            idB = panelId;
        else
            idA = panelId;
        front = 1 - front;
        live.opacity = 0;
        live.scale = contentScale;
        swap.start();
    }

    ParallelAnimation {
        id: swap
        NumberAnimation {
            target: root.leaving
            property: "opacity"
            to: 0
            duration: Motion.contentOut + 40
            easing.type: Motion.exitEasing
        }
        NumberAnimation {
            target: root.leaving
            property: "scale"
            to: root.contentScale
            duration: Motion.contentOut + 40
            easing.type: Motion.exitEasing
        }
        SequentialAnimation {
            PauseAnimation {
                duration: Motion.contentOut / 2
            }
            ParallelAnimation {
                NumberAnimation {
                    target: root.live
                    property: "opacity"
                    to: 1
                    duration: Motion.contentIn + 80
                    easing.type: Motion.enterEasing
                }
                NumberAnimation {
                    target: root.live
                    property: "scale"
                    to: 1
                    duration: Motion.spatial
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Motion.spatialCurve
                }
            }
        }
        onFinished: {
            // the old slot lets its panel go
            if (root.front === 0)
                root.idB = "";
            else
                root.idA = "";
            root.leaving.opacity = 1;
            root.leaving.scale = 1;
        }
    }

    function wire(item: Item): void {
        item.screen = Qt.binding(() => root.screen);
        item.visibleProgress = Qt.binding(() => root.visibleProgress);
        if (item.context !== undefined)
            item.context = Qt.binding(() => root.context);
        if (item.showings !== undefined)
            item.showings = Qt.binding(() => root.showings);
        if (item.active !== undefined)
            item.active = Qt.binding(() => root.active);
        if (item.canGoBack !== undefined) {
            item.canGoBack = Qt.binding(() => root.history.length > 0);
            item.back.connect(() => PanelRouter.back(root.screen.name));
        }
    }

    Component {
        id: home
        HomePanel {}
    }
    Component {
        id: media
        MediaPanel {}
    }
    Component {
        id: system
        SystemPanel {}
    }
    Component {
        id: network
        NetworkPanel {}
    }
    Component {
        id: bluetooth
        BluetoothPanel {}
    }
    Component {
        id: launcher
        LauncherPanel {}
    }
    Component {
        id: clipboard
        ClipboardPanel {}
    }
    Component {
        id: notifications
        NotificationsPanel {}
    }
    Component {
        id: quick
        QuickSettingsPanel {}
    }
    Component {
        id: wallpaper
        WallpaperPanel {}
    }
    Component {
        id: session
        SessionPanel {}
    }
    Component {
        id: control
        ControlPanel {}
    }
    // the native Control Center's tabs, as pages of their own
    Component {
        id: audioPage
        ModulePage {
            kind: "audio"
        }
    }
    Component {
        id: powerPage
        ModulePage {
            kind: "power"
        }
    }
    Component {
        id: monitorPage
        ModulePage {
            kind: "monitor"
        }
    }
    Component {
        id: calendarPage
        ModulePage {
            kind: "calendar"
        }
    }
    Component {
        id: weatherPage
        ModulePage {
            kind: "weather"
        }
    }
    Component {
        id: mediaPage
        ModulePage {
            kind: "media"
        }
    }
    Component {
        id: screenTimePage
        ModulePage {
            kind: "screen-time"
        }
    }

    PanelHero {
        id: hero
        visible: root.heroShown
        width: parent.width
        height: root.heroShown ? implicitHeight : 0
        active: root.active && root.heroShown
    }
    PanelTabs {
        id: tabStrip
        visible: root.tabbed
        x: Metrics.s5
        y: (root.heroShown ? hero.height : 0) + Metrics.s3
        width: parent.width - Metrics.s5 * 2
        height: root.tabbed ? implicitHeight + Metrics.s3 : 0
        tabs: root.tabs
        current: root.tabId
        showIcons: root.cfg.tab_icons_shown ?? true
        showLabels: root.cfg.tab_labels_shown ?? true
        style: root.cfg.tab_style ?? "inline"
        onPicked: id => PanelRouter.switchTo(id, root.screen.name)
    }

    Loader {
        id: slotA
        y: root.contentTop
        width: parent.width
        transformOrigin: Item.Top
        visible: root.idA !== ""
        sourceComponent: root.idA !== "" ? (root.panels[root.idA] ?? null) : null
        onLoaded: root.wire(item)
    }
    Loader {
        id: slotB
        y: root.contentTop
        width: parent.width
        transformOrigin: Item.Top
        visible: root.idB !== ""
        sourceComponent: root.idB !== "" ? (root.panels[root.idB] ?? null) : null
        onLoaded: root.wire(item)
    }
}
