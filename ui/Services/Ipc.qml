pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Zynith.Native

// `quickshell -p <ui>/shell.qml ipc call zynith <method> [args]`
Singleton {
    id: root

    // the output with keyboard focus under niri, else the first one
    function focusedScreen(): string {
        const focused = Workspaces.focusedOutput;
        if (focused && Quickshell.screens.some(s => s.name === focused))
            return focused;
        return Quickshell.screens.length > 0 ? Quickshell.screens[0].name : "";
    }

    IpcHandler {
        target: "zynith"

        function panel(id: string): void {
            PanelRouter.toggle(id, root.focusedScreen(), null);
        }
        function launcher(): void {
            PanelRouter.toggle("launcher", root.focusedScreen(), { edge: "center" });
        }
        function quick(): void {
            PanelRouter.toggle("quick", root.focusedScreen(), null);
        }
        function clipboard(): void {
            PanelRouter.toggle("clipboard", root.focusedScreen(), { edge: "center" });
        }
        // what the launcher would list for a query, best first
        function apps(query: string): string {
            return Apps.search(query, 8).map(e => e.name + "  [" + e.id + "]").join("\n");
        }
        function dnd(on: string): string {
            Notifications.setDnd(on === "on" || on === "true" || (on === "toggle" && !Notifications.dnd));
            return Notifications.dnd ? "on" : "off";
        }
        // config | scrolling | tiling-like
        function behaviour(name: string): string {
            Config.setWindowBehaviour(name);
            return Config.window.behaviour;
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
                network: { connected: Network.connected, kind: NetworkState.kind, strength: Number(Network.strength.toFixed(2)), wifi: Network.wifiEnabled, listed: Network.networks.length, consumers: NetworkState.consumers },
                notifications: { serving: Notifications.serving, wanted: Notifications.wanted, history: Notifications.history.length, popups: Notifications.popups.length, dnd: Notifications.dnd },
                windowBehaviour: { value: Config.window.behaviour, included: WindowBehaviour.included, error: WindowBehaviour.status },
                launchTime: Quickshell.launchTime
            });
        }
    }
}
