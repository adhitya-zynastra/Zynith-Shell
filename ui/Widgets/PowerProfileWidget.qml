import QtQuick
import Quickshell.Services.UPower
import qs.Common
import qs.Components

// The system power profile; click steps saver → balanced → performance.
BarItem {
    id: root

    readonly property int profile: PowerProfiles.profile
    onClicked: {
        const order = PowerProfiles.hasPerformanceProfile ? [PowerProfile.PowerSaver, PowerProfile.Balanced, PowerProfile.Performance] : [PowerProfile.PowerSaver, PowerProfile.Balanced];
        PowerProfiles.profile = order[(order.indexOf(profile) + 1) % order.length];
    }

    Icon {
        name: root.profile === PowerProfile.PowerSaver ? "leaf" : root.profile === PowerProfile.Performance ? "rocket" : "gauge"
        tone: root.profile === PowerProfile.PowerSaver ? "accent" : "ink"
    }
}
