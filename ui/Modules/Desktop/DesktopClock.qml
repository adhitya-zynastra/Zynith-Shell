import QtQuick
import qs.Common
import qs.Services
import "../../Common/Strftime.js" as Strftime

// Text from the time, fitted to its box: a big hour, a small date, whatever the format says.
Text {
    property var settings: ({})
    readonly property string format: Strftime.toQt(settings.format ?? "%H:%M")
    text: Qt.formatDateTime(Time.now, format)
    font.family: settings.font_family ?? Type.display
    font.pixelSize: Math.max(8, height * 0.92)
    fontSizeMode: Text.Fit
    minimumPixelSize: 6
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    color: Theme.pal(settings.color ?? "on_surface")
}
