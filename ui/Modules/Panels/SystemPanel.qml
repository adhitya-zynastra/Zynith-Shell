import QtQuick
import Quickshell.Io
import qs.Common
import qs.Components
import qs.Services

// What the machine is and how hard it is working. Samplers run only while this panel exists.
Column {
    id: root

    property var screen: null
    property real visibleProgress: 1
    property bool canGoBack: false
    signal back

    padding: Metrics.s6
    spacing: Metrics.s5
    readonly property real inner: width - padding * 2

    property string kernel: ""
    property string model: ""
    property real uptime: 0

    Component.onCompleted: System.retain()
    Component.onDestruction: System.release()

    FileView {
        path: "/proc/sys/kernel/osrelease"
        onLoaded: root.kernel = text().trim()
    }
    FileView {
        path: "/sys/class/dmi/id/product_version"
        printErrors: false
        onLoaded: root.model = text().trim()
    }
    FileView {
        id: uptimeFile
        path: "/proc/uptime"
        onLoaded: root.uptime = parseFloat(text())
    }
    Timer {
        running: true
        repeat: true
        interval: 60000
        onTriggered: uptimeFile.reload()
    }

    function duration(s: real): string {
        const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
        return (d > 0 ? d + "d " : "") + h + "h " + m + "m";
    }

    PanelHeader {
        width: root.inner
        title: "System"
        caption: root.model || "This machine"
        canGoBack: root.canGoBack
        onBack: root.back()
    }

    Row {
        width: root.inner
        spacing: Metrics.s5

        Meter {
            width: (parent.width - parent.spacing) / 2
            label: "CPU"
            value: System.cpu
        }
        Meter {
            width: (parent.width - parent.spacing) / 2
            label: "Memory"
            value: System.memUsed
            readout: (System.memUsed * System.memTotalGiB).toFixed(1) + " / " + System.memTotalGiB.toFixed(0) + " GB"
        }
    }

    Meter {
        visible: Power.present
        width: root.inner
        label: Power.charging ? "Battery · charging" : "Battery"
        value: Power.level
    }

    Column {
        width: root.inner
        spacing: Metrics.s2

        Repeater {
            model: [
                ["Processor", Hardware.cpuModel + "  ·  " + Hardware.cpuThreads + " threads"],
                ["Graphics", Hardware.gpuSummary],
                ["Kernel", root.kernel],
                ["Uptime", root.duration(root.uptime)],
                ["Experience", (ExperiencePolicy.labels[ExperiencePolicy.profile] ?? "") + (ExperiencePolicy.automatic ? "  ·  auto" : "")]
            ]

            delegate: Item {
                required property var modelData
                width: root.inner
                height: 20

                Label {
                    role: "caption"
                    tone: "faint"
                    caps: true
                    text: parent.modelData[0]
                }
                Label {
                    anchors.right: parent.right
                    width: parent.width * 0.68
                    horizontalAlignment: Text.AlignRight
                    role: "label"
                    tone: "muted"
                    text: parent.modelData[1]
                }
            }
        }
    }
}
