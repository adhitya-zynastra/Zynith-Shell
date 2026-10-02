import QtQuick
import QtQuick.Effects
import qs.Common
import qs.Components
import qs.Services

// Now, and (if asked) the days ahead, scaled to the box. Reads what the native shell already fetched.
Item {
    id: root
    property var settings: ({})
    function opt(key: string): var {
        return WidgetTypes.value("weather", settings, key);
    }
    readonly property var w: Weather.data
    readonly property color ink: Theme.colour(opt("color"))
    readonly property string family: (opt("font_family") ?? "") !== "" ? opt("font_family") : Type.ui
    readonly property bool forecast: opt("show_forecast") === true
    readonly property int days: Math.max(1, Math.min(6, opt("forecast_days") ?? 3))
    // everything below is laid out at 320 × (forecast ? 140 : 70) and scaled into the box
    readonly property real unit: Math.min(width / 320, height / (forecast ? 140 : 70))
    implicitWidth: 320
    implicitHeight: forecast ? 140 : 70

    Component.onCompleted: Weather.retain()
    Component.onDestruction: Weather.release()

    layer.enabled: opt("shadow") === true
    layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: Theme.shadow
        shadowBlur: 0.6
        shadowVerticalOffset: 2
    }

    Column {
        visible: Weather.valid
        anchors.centerIn: parent
        spacing: 10 * root.unit

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 10 * root.unit
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                name: Weather.glyph(root.w.current?.code ?? 0, root.w.current?.isDay ?? true)
                size: 34 * root.unit
                color: root.ink
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Math.round(root.w.current?.temperature ?? 0) + (root.w.unit ?? "°")
                font.family: (root.settings.font_family ?? "") !== "" ? root.family : Type.display
                font.pixelSize: 40 * root.unit
                font.weight: Font.Light
                color: root.ink
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.w.location ?? ""
                font.family: root.family
                font.pixelSize: 13 * root.unit
                color: Theme.alpha(root.ink, 0.7)
            }
        }
        Row {
            visible: root.forecast
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 18 * root.unit
            Repeater {
                model: (root.w.days ?? []).slice(1, 1 + root.days)
                delegate: Column {
                    required property var modelData
                    spacing: 3 * root.unit
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Qt.formatDate(new Date(modelData.date + "T12:00:00"), "ddd").toUpperCase()
                        font.family: root.family
                        font.pixelSize: 10 * root.unit
                        font.letterSpacing: Type.tracking
                        color: Theme.alpha(root.ink, 0.6)
                    }
                    Icon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        name: Weather.glyph(modelData.code, true)
                        size: 18 * root.unit
                        color: root.ink
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Math.round(modelData.max) + "° " + Math.round(modelData.min) + "°"
                        font.family: root.family
                        font.pixelSize: 11 * root.unit
                        color: Theme.alpha(root.ink, 0.8)
                    }
                }
            }
        }
    }
    Text {
        visible: !Weather.valid
        anchors.centerIn: parent
        text: "Weather is loading"
        font.family: root.family
        font.pixelSize: 13 * Math.max(0.6, root.unit)
        color: Theme.alpha(root.ink, 0.6)
    }
}
