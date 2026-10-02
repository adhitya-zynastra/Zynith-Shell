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
    readonly property bool powerSaver: PowerProfiles.profile === PowerProfile.PowerSaver

    // set below 20 %, cleared above 25 % so a battery hovering at the edge does not flap
    property bool low: false
    function updateLow(): void {
        if (!present || charging || !onBattery)
            low = false;
        else if (level < 0.2)
            low = true;
        else if (level > 0.25)
            low = false;
    }
    onLevelChanged: updateLow()
    onChargingChanged: updateLow()
    onOnBatteryChanged: updateLow()
    onPresentChanged: updateLow()

    readonly property string glyph: charging ? "battery-charging" : level > 0.85 ? "battery-4" : level > 0.6 ? "battery-3" : level > 0.35 ? "battery-2" : level > 0.12 ? "battery-1" : "battery"
}
