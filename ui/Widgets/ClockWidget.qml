import QtQuick
import Quickshell
import qs.Common
import qs.Components
import qs.Services
import Quickshell.Io
import "../Common/Strftime.js" as Strftime

// The time, in its format (a line break in the format stacks lines), stacked hours over minutes on a
// vertical bar unless vertical_format says otherwise. The tooltip has its own format; a time zone shifts it.
BarItem {
    id: root
    spacing: 0
    readonly property string format: opt("format") ?? "{:%H:%M}"
    readonly property string verticalFormat: opt("vertical_format") ?? ""
    // seconds tick the whole UI's clock (every binding on the time, every window drawing one), so they are
    // asked for only by a format that shows them — the tooltip's only while the tooltip is up
    readonly property bool wantsSeconds: /%S|%T|%r/.test(format + verticalFormat) || (tipReady && hovered && /%S|%T|%r/.test(opt("tooltip_format") ?? ""))
    onWantsSecondsChanged: wantsSeconds ? Time.retainSeconds() : Time.releaseSeconds()
    Component.onCompleted: if (wantsSeconds)
        Time.retainSeconds()
    Component.onDestruction: if (wantsSeconds)
        Time.releaseSeconds()

    // another zone's offset, asked once per zone
    readonly property string zone: opt("timezone") ?? ""
    property int offsetMinutes: 0
    onZoneChanged: if (zone !== "")
        tz.running = true
    Process {
        id: tz
        command: ["sh", "-c", "TZ=\"$1\" date +%z", "zynith-tz", root.zone]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = text.trim().match(/^([+-])(\d\d)(\d\d)$/);
                root.offsetMinutes = m ? (m[1] === "-" ? -1 : 1) * (parseInt(m[2]) * 60 + parseInt(m[3])) : 0;
            }
        }
    }
    readonly property date time: zone !== "" ? new Date(Time.now.getTime() + (offsetMinutes + Time.now.getTimezoneOffset()) * 60000) : Time.now
    // "{:%H}\n{:%M}" or "{:%H:%M:%S}\n{:%A}": each {:…} through strftime; a line with no braces is one format
    function render(fmt: string): string {
        return fmt.replace(/\\n/g, "\n").split("\n").map(line => line.indexOf("{:") >= 0 ? line.replace(/\{:([^}]*)\}/g, (m, f) => Qt.formatDateTime(root.time, Strftime.toQt(f))) : Qt.formatDateTime(root.time, Strftime.toQt(line))).join("\n");
    }
    readonly property string shownText: vertical ? render(verticalFormat !== "" ? verticalFormat : "{:%H}\n{:%M}") : render(format)
    tooltip: (opt("tooltip_format") ?? "") !== "" ? render(opt("tooltip_format")) : ""

    BarText {
        item: root
        size: Type.title
        // medium unless the widget or its bar sets a weight (Bars → Text weight)
        font.weight: (root.opt("font_weight") ?? root.bar?.spec?.font_weight) !== undefined ? root.weight : Font.Medium
        horizontalAlignment: Text.AlignHCenter
        lineHeight: 0.92
        text: root.shownText
    }
}
