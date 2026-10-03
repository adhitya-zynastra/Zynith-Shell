import QtQuick
import Quickshell
import qs.Common
import qs.Components
import qs.Services
import Quickshell.Services.UPower

// The power profile: saver, balanced or performance.
BarItem {
    id: root
    readonly property int profile: PowerProfiles.profile
    BarGlyph {
        item: root
        name: root.profile === PowerProfile.PowerSaver ? "leaf" : root.profile === PowerProfile.Performance ? "gauge" : "scale"
    }
}
