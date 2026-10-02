pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.UPower

Singleton {
    id: root

    readonly property UPowerDevice device: UPower.displayDevice
    readonly property bool present: device !== null && device.ready && device.isPresent && (device.isLaptopBattery || device.type === UPowerDeviceType.Battery)
    // UPower reports 0..1 here
    readonly property real level: present ? device.percentage : 0
    readonly property bool charging: present && (device.state === UPowerDeviceState.Charging || device.state === UPowerDeviceState.FullyCharged || device.state === UPowerDeviceState.PendingCharge)
    readonly property bool onBattery: UPower.onBattery

    readonly property string glyph: charging ? "battery-charging" : level > 0.85 ? "battery-4" : level > 0.6 ? "battery-3" : level > 0.35 ? "battery-2" : level > 0.12 ? "battery-1" : "battery"
}
