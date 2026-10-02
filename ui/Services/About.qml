pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

// Static facts for Settings → Home/About, read once when first used: who, which system, which software.
Singleton {
    id: root

    readonly property string user: Quickshell.env("USER") || ""
    property string realName: ""
    property string os: ""
    property string kernel: ""
    property string host: ""
    property string timezone: ""
    property string niriVersion: ""
    property string quickshellVersion: ""
    readonly property string zynithVersion: Quickshell.env("ZYNITH_VERSION") || "development"
    // the system account picture (AccountsService), the same one the login screen shows
    readonly property string avatar: "file:///var/lib/AccountsService/icons/" + user

    FileView {
        path: "/etc/passwd"
        onLoaded: {
            const line = text().split("\n").find(l => l.startsWith(root.user + ":"));
            const gecos = line ? line.split(":")[4] ?? "" : "";
            root.realName = gecos.split(",")[0] || root.user;
        }
    }
    FileView {
        path: "/etc/os-release"
        onLoaded: root.os = ((text().match(/^PRETTY_NAME="?([^"\n]*)"?$/m) || [])[1] || "Linux")
    }
    FileView {
        path: "/proc/sys/kernel/osrelease"
        onLoaded: root.kernel = text().trim()
    }
    FileView {
        path: "/sys/class/dmi/id/product_version"
        printErrors: false
        onLoaded: root.host = text().trim()
    }

    // one-shot reads; nothing here repeats
    Process {
        running: true
        command: ["timedatectl", "show", "-p", "Timezone", "--value"]
        stdout: StdioCollector {
            onStreamFinished: root.timezone = text.trim()
        }
    }
    Process {
        running: true
        command: ["/usr/bin/quickshell", "--version"]
        stdout: StdioCollector {
            onStreamFinished: root.quickshellVersion = (text.match(/Quickshell\s+([^\s]+)/) || [])[1] || ""
        }
    }
    Process {
        running: true
        command: ["niri", "--version"]
        stdout: StdioCollector {
            onStreamFinished: root.niriVersion = text.trim().replace(/^niri\s*/, "")
        }
    }
}
