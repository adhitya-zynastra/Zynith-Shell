import QtQuick
import Zynith.Native
import qs.Common
import qs.Components
import qs.Services

Column {
    spacing: Metrics.s5

    PanelHeader {
        width: parent.width
        title: "Wallpaper"
        caption: "One wallpaper state drives the desktop, the overview, the lock screen and the colours"
    }

    Card {
        width: parent.width
        caption: "Browser"

        SettingChoice {
            title: "Layout"
            detail: "Carousel: a cinematic arc across the dimmed desktop. Grid: a panel with the focused wallpaper above a grid. L switches while browsing"
            domain: "wallpaper"
            key: "layout"
            options: [{ key: "carousel", label: "Carousel" }, { key: "grid", label: "Grid" }]
        }
        SettingSlider {
            title: "Carousel card"
            detail: "Width of the focused card; Auto is 40 % of the screen, at most 760 px"
            domain: "wallpaper"
            key: "card_width"
            from: 0
            to: 1400
            step: 20
            format: v => v < 320 ? "Auto" : Math.round(v) + " px"
        }
    }

    Card {
        width: parent.width
        caption: "Images"

        SettingText {
            title: "Folder"
            detail: "Where the wallpaper browser looks"
            domain: "wallpaper"
            key: "directory"
            placeholder: "~/Pictures/wallpapers"
        }
    }

    Card {
        width: parent.width
        caption: "Live wallpaper"

        SettingChoice {
            title: "Overview"
            detail: "Live shows the running wallpaper behind niri's overview; Poster shows its still image, which costs nothing"
            domain: "wallpaper"
            key: "overview"
            options: [{ key: "poster", label: "Poster" }, { key: "live", label: "Live" }]
        }
        SettingChoice {
            title: "Lock screen"
            detail: "The lock screen shows the poster for now"
            domain: "wallpaper"
            key: "lock"
            options: [{ key: "poster", label: "Poster" }]
        }
    }

    // the change itself: the native shell's transition effects, read from its registry and written as its
    // own Settings would (settings-set)
    Card {
        id: transitions
        width: parent.width
        caption: "Changing wallpaper"
        property var entries: []
        function read(): void {
            CoreClient.call("settings-schema wallpaper", text => {
                try {
                    transitions.entries = JSON.parse(text).entries.filter(e => e.path[0] === "wallpaper" && String(e.path[1]).startsWith("transition"));
                } catch (e) {}
            });
        }
        Component.onCompleted: read()
        SchemaForm {
            width: parent.width
            schema: transitions.entries.map(e => ({
                        key: e.path.join("."),
                        label: e.title,
                        hint: e.subtitle,
                        kind: e.kind === "multi" ? "multi" : e.kind === "slider" ? "int" : e.kind,
                        options: (e.options ?? []).map(o => ({ key: o.value, label: o.label })),
                        from: e.min,
                        to: e.max,
                        step: e.step || 50,
                        value: e.value,
                        overridden: e.overridden
                    }))
            valueOf: key => schema.find(s => s.key === key)?.value
            isSet: key => schema.find(s => s.key === key)?.overridden === true
            onChanged: (key, value) => CoreClient.call("settings-set " + JSON.stringify({ path: key.split("."), value: typeof value === "object" ? Array.from(value) : value }), () => transitions.read())
            onCleared: key => CoreClient.call("settings-reset " + JSON.stringify({ path: key.split(".") }), () => transitions.read())
        }
        SchemaForm {
            width: parent.width
            readonly property var own: Config.wallpaper ?? ({})
            schema: [{ key: "close_on_apply", label: "The browser closes once one is applied", kind: "toggle", default: false }]
            valueOf: key => own[key] ?? false
            onChanged: (key, value) => Config.change("wallpaper", key, value, labelOf(key))
        }
    }
}
