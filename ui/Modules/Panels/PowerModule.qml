import QtQuick
import Quickshell.Services.UPower
import Zynith.Native
import qs.Common
import qs.Components
import qs.Services

// Power: the system profile and Zynith's Experience profile, the battery, its charge limit (UPower's preset,
// through the native charge-limit), and the batteries of what is paired. The page adds the battery's health
// and capacity, every peripheral, and the Experience profile picker.
Column {
    id: root

    property var screen: null
    property bool active: true
    property bool expanded: false

    readonly property var battery: Power.device
    spacing: Metrics.s3

    // the charge limit, asked for when shown
    property var limit: ({ supported: false })
    function readLimit(): void {
        CoreClient.call("charge-limit", text => {
            try {
                root.limit = JSON.parse(text);
            } catch (e) {
                root.limit = { supported: false };
            }
        });
    }
    onActiveChanged: if (active && Power.present)
        readLimit()
    Component.onCompleted: if (Power.present)
        readLimit()

    function duration(s: real): string {
        if (!(s > 0))
            return "";
        const h = Math.floor(s / 3600), m = Math.round(s % 3600 / 60);
        return h > 0 ? h + "h " + m + "m" : m + "m";
    }
    readonly property string batteryLine: {
        if (!Power.present)
            return "";
        const pct = Math.round(Power.level * 100) + "%";
        const st = battery.state;
        if (st === UPowerDeviceState.FullyCharged)
            return pct + " · full";
        if (st === UPowerDeviceState.Charging)
            return pct + " · charging" + (battery.timeToFull > 0 ? ", full in " + duration(battery.timeToFull) : "");
        if (st === UPowerDeviceState.PendingCharge)
            return pct + " · plugged in, held";
        if (st === UPowerDeviceState.Discharging)
            return pct + (battery.timeToEmpty > 0 ? " · " + duration(battery.timeToEmpty) + " left" : " · on battery");
        return pct;
    }

    // ── header: the profile in use (the Control Panel's section head names the section; here, the Experience) ──
    Item {
        width: root.width
        height: 16
        Label {
            role: "data"
            tone: "faint"
            text: root.expanded ? "Profile" : ""
            MouseArea {
                anchors.fill: parent
                enabled: !root.expanded
                cursorShape: Qt.PointingHandCursor
                onClicked: PanelRouter.navigate("power", root.screen.name)
            }
        }
        Label {
            anchors.right: parent.right
            role: "data"
            tone: ExperiencePolicy.automatic ? "accent" : "faint"
            text: "Experience · " + (ExperiencePolicy.labels[ExperiencePolicy.profile] ?? "") + (ExperiencePolicy.automatic ? " · auto" : "")
        }
    }
    Segmented {
        width: root.width
        current: ControlShortcuts.profile
        options: PowerProfiles.hasPerformanceProfile ? [{ key: "saver", label: "Saver" }, { key: "balanced", label: "Balanced" }, { key: "performance", label: "Performance" }] : [{ key: "saver", label: "Saver" }, { key: "balanced", label: "Balanced" }]
        onPicked: key => PowerProfiles.profile = key === "saver" ? PowerProfile.PowerSaver : key === "performance" ? PowerProfile.Performance : PowerProfile.Balanced
    }
    Label {
        visible: PowerProfiles.degradationReason !== PerformanceDegradationReason.None && ControlShortcuts.profile === "performance"
        width: root.width
        role: "caption"
        tone: "faint"
        wrapMode: Text.WordWrap
        text: "Performance is held back: " + PerformanceDegradationReason.toString(PowerProfiles.degradationReason).replace(/([a-z])([A-Z])/g, "$1 $2").toLowerCase()
    }

    // ── the battery ──
    Item {
        visible: Power.present
        width: root.width
        height: 44
        Icon {
            id: battIcon
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            name: Power.glyph
            size: 20
            tone: Power.low ? "danger" : Power.charging ? "accent" : "muted"
        }
        Column {
            anchors.left: battIcon.right
            anchors.leftMargin: Metrics.s3
            anchors.right: limitToggle.left
            anchors.rightMargin: Metrics.s3
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Label {
                width: parent.width
                role: "label"
                elide: Text.ElideRight
                text: root.batteryLine
            }
            // fill
            Rectangle {
                width: parent.width
                height: 4
                radius: 2
                color: Theme.well
                Rectangle {
                    width: parent.width * Power.level
                    height: parent.height
                    radius: 2
                    color: Power.low ? Theme.danger : Theme.alpha(Theme.ink, 0.78)
                    Behavior on width {
                        Anim {
                            role: "spatial"
                        }
                    }
                }
                // where the charge limit stops
                Rectangle {
                    visible: root.limit.enabled === true && root.limit.end !== undefined
                    x: parent.width * (root.limit.end ?? 100) / 100 - 1
                    y: -2
                    width: 2
                    height: 8
                    radius: 1
                    color: Theme.inkMuted
                }
            }
        }
        Column {
            id: limitToggle
            visible: root.limit.supported === true
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Label {
                anchors.right: parent.right
                role: "micro"
                tone: "faint"
                text: "Limit" + (root.limit.end !== undefined ? " " + root.limit.end + "%" : "")
            }
            Toggle {
                anchors.right: parent.right
                enabled: root.limit.settable === true
                opacity: enabled ? 1 : Theme.disabledOpacity
                checked: root.limit.enabled === true
                onToggled: {
                    const on = !checked;
                    root.limit = Object.assign({}, root.limit, { enabled: on });
                    CoreClient.call("charge-limit " + (on ? "on" : "off"), () => root.readLimit());
                }
            }
        }
    }

    // ── the page: health, capacity, rate ──
    Grid {
        id: facts
        visible: root.expanded && Power.present
        width: root.width
        columns: 3
        rowSpacing: Metrics.s3
        columnSpacing: Metrics.s3
        readonly property real cell: (width - columnSpacing * 2) / 3
        Repeater {
            model: [
                { label: "Health", value: root.limit.health !== undefined ? Math.round(root.limit.health) + "%" : root.battery?.healthSupported ? Math.round(root.battery.healthPercentage) + "%" : "—" },
                { label: "Capacity", value: root.limit.energy_full ? root.limit.energy_full.toFixed(1) + " / " + root.limit.energy_full_design.toFixed(0) + " Wh" : (root.battery?.energyCapacity ?? 0).toFixed(1) + " Wh" },
                { label: Power.charging ? "Charging at" : "Drawing", value: Math.abs(root.battery?.changeRate ?? 0) < 0.05 ? (Power.onBattery ? "—" : "Idle") : Math.abs(root.battery.changeRate).toFixed(1) + " W" }
            ]
            delegate: Rectangle {
                required property var modelData
                width: facts.cell
                height: 54
                radius: Metrics.radiusLg
                color: Theme.well
                Column {
                    anchors.left: parent.left
                    anchors.leftMargin: Metrics.s3
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Label {
                        role: "caption"
                        tone: "faint"
                        text: modelData.label
                    }
                    Label {
                        role: "label"
                        numeric: true
                        text: modelData.value
                    }
                }
            }
        }
    }
    Label {
        visible: root.expanded && root.limit.supported === true && root.limit.start !== undefined
        width: root.width
        role: "caption"
        tone: "faint"
        wrapMode: Text.WordWrap
        text: "With the limit on, charging starts below " + (root.limit.start ?? 0) + "% and stops at " + (root.limit.end ?? 100) + "%" + (root.limit.settable ? "" : " (set by the firmware)") + "."
    }

    // ── what else has a battery ──
    readonly property var peripherals: UPower.devices.values.filter(d => d.ready && d.isPresent && !d.isLaptopBattery && d.type !== UPowerDeviceType.LinePower && d.type !== UPowerDeviceType.Battery && d.percentage > 0)
    function peripheralIcon(t: int): string {
        return t === UPowerDeviceType.Mouse ? "mouse" : t === UPowerDeviceType.Keyboard ? "keyboard" : t === UPowerDeviceType.Phone || t === UPowerDeviceType.Tablet ? "device-mobile" : t === UPowerDeviceType.Headset ? "headset" : t === UPowerDeviceType.Headphones ? "headphones" : t === UPowerDeviceType.GamingInput ? "device-gamepad-2" : t === UPowerDeviceType.Speakers ? "device-speaker" : t === UPowerDeviceType.Wearable ? "device-watch" : "battery-2";
    }
    Column {
        visible: root.peripherals.length > 0
        width: root.width
        spacing: Metrics.s1
        Label {
            visible: root.expanded
            role: "caption"
            tone: "faint"
            caps: true
            text: "Devices"
        }
        Flow {
            width: parent.width
            spacing: Metrics.s2
            Repeater {
                model: root.expanded ? root.peripherals : root.peripherals.slice(0, 4)
                delegate: Rectangle {
                    required property var modelData
                    width: root.expanded ? root.width : chipRow.implicitWidth + Metrics.s4 * 2
                    height: root.expanded ? 40 : 28
                    radius: height / 2
                    color: Theme.well
                    Row {
                        id: chipRow
                        anchors.left: parent.left
                        anchors.leftMargin: Metrics.s4
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Metrics.s2
                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: root.peripheralIcon(modelData.type)
                            size: 14
                            tone: modelData.percentage < 0.2 ? "danger" : "muted"
                        }
                        Label {
                            visible: root.expanded
                            anchors.verticalCenter: parent.verticalCenter
                            role: "label"
                            text: modelData.model || UPowerDeviceType.toString(modelData.type)
                        }
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            role: "label"
                            numeric: true
                            tone: root.expanded ? "faint" : "ink"
                            text: Math.round(modelData.percentage * 100) + "%"
                        }
                    }
                }
            }
        }
    }

    // ── the Experience profile (the page) ──
    Column {
        visible: root.expanded
        width: root.width
        spacing: Metrics.s2
        Label {
            role: "caption"
            tone: "faint"
            caps: true
            text: "Experience" + (ExperiencePolicy.limitedBy !== "" ? " · held by " + ExperiencePolicy.limitedBy.toLowerCase() : "")
        }
        Segmented {
            width: parent.width
            current: ExperiencePolicy.automatic ? "auto" : ExperiencePolicy.selected
            options: [{ key: "auto", label: "Auto" }, { key: "performance", label: "Light" }, { key: "balanced", label: "Balanced" }, { key: "enhanced", label: "Enhanced" }, { key: "max", label: "Max" }]
            onPicked: key => ExperiencePolicy.select(key)
        }
    }
}
