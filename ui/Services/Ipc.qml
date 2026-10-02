pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// `quickshell -p <ui>/shell.qml ipc call zynith <method> [args]`
Singleton {
    id: root

    function focusedScreen(): string {
        return Quickshell.screens.length > 0 ? Quickshell.screens[0].name : "";
    }

    IpcHandler {
        target: "zynith"

        function panel(id: string): void {
            PanelRouter.toggle(id, root.focusedScreen(), null);
        }
        function close(): void {
            PanelRouter.closeAll();
        }
        function profile(name: string): string {
            ExperiencePolicy.select(name);
            return ExperiencePolicy.profile;
        }
        function stats(): string {
            return JSON.stringify(Diagnostics.summary());
        }
        function resetStats(): void {
            Diagnostics.reset();
        }
        function status(): string {
            return JSON.stringify({
                profile: ExperiencePolicy.profile,
                selected: ExperiencePolicy.selected,
                recommended: ExperiencePolicy.recommended,
                hardwareProfile: ExperiencePolicy.hardwareProfile,
                limitedBy: ExperiencePolicy.limitedBy,
                power: { onBattery: Power.onBattery, level: Number(Power.level.toFixed(2)), low: Power.low, powerSaver: Power.powerSaver },
                tier: Hardware.tier,
                cpu: Hardware.cpuModel,
                threads: Hardware.cpuThreads,
                memGiB: Number(Hardware.memGiB.toFixed(1)),
                gpus: Hardware.gpus.map(g => g.label),
                palette: Scheme.live ? "theme" : "fallback",
                niri: Workspaces.niri,
                overview: Workspaces.overviewOpen,
                workspaces: Workspaces.forScreen(Quickshell.screens[0]).map(w => (w.active ? "*" : "") + w.windows),
                focused: Workspaces.focusedWindow.appId ?? "",
                spectrum: { consumers: Spectrum.consumers, active: Spectrum.active, bands: Spectrum.values.length },
                panels: PanelRouter.openPanels,
                launchTime: Quickshell.launchTime
            });
        }
    }
}
