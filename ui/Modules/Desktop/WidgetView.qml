import QtQuick
import qs.Common
import qs.Components
import qs.Services

// One desktop widget's content: its kind's component, over the common background when it has one. Used on
// the desktop, in the editor and in the add-widget picker, so a widget looks the same in all three.
Item {
    id: root

    property var spec: ({})
    // shown in the editor or the picker: widgets that would be empty (silence) draw a stand-in
    property bool preview: false
    readonly property string type: WidgetTypes.canonical(spec.type ?? "")
    readonly property var settings: spec.settings ?? ({})
    function opt(key: string): var {
        return WidgetTypes.value(type, settings, key);
    }
    readonly property bool interactive: loader.item?.interactive ?? false
    readonly property bool backed: opt("background") === true && type !== "button" && type !== "session_actions"
    readonly property real padding: backed ? (opt("background_padding") ?? 10) : 0
    implicitWidth: loader.item?.implicitWidth ?? 0
    implicitHeight: loader.item?.implicitHeight ?? 0

    Rectangle {
        visible: root.backed
        anchors.fill: parent
        radius: root.opt("background_radius") ?? 12
        color: Theme.alpha(Theme.colour(root.opt("background_color") ?? "surface"), root.opt("background_opacity") ?? 0.8)
        border.width: Theme.hairlineWidth
        border.color: Theme.hairline
    }

    Loader {
        id: loader
        anchors.fill: parent
        anchors.margins: root.padding
        sourceComponent: ({
                clock: clock,
                label: label,
                sticker: sticker,
                audio_visualizer: visualizer,
                weather: weather,
                media_player: media,
                calendar: calendar,
                sysmon: sysmon,
                volume: volume,
                session_actions: session,
                button: button
            })[root.type] ?? unknown
        onLoaded: {
            item.settings = Qt.binding(() => root.settings);
            if (item.preview !== undefined)
                item.preview = Qt.binding(() => root.preview);
        }
    }

    Component {
        id: clock
        DesktopClock {}
    }
    Component {
        id: label
        DesktopLabel {}
    }
    Component {
        id: sticker
        DesktopSticker {}
    }
    Component {
        id: visualizer
        DesktopVisualizer {}
    }
    Component {
        id: weather
        DesktopWeather {}
    }
    Component {
        id: media
        DesktopMedia {}
    }
    Component {
        id: calendar
        DesktopCalendar {}
    }
    Component {
        id: sysmon
        DesktopSysmon {}
    }
    Component {
        id: volume
        DesktopVolume {}
    }
    Component {
        id: session
        DesktopSession {}
    }
    Component {
        id: button
        DesktopButton {}
    }
    // a kind this build does not know (a plugin's): say so instead of leaving a hole
    Component {
        id: unknown
        Item {
            property var settings
            Text {
                anchors.centerIn: parent
                text: root.spec.type ?? ""
                color: Theme.inkFaint
                font.family: Type.ui
                font.pixelSize: 12
            }
        }
    }
}
