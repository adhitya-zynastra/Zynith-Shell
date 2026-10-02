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
        function status(): string {
            return JSON.stringify({
                profile: ExperiencePolicy.profile,
                selected: ExperiencePolicy.selected,
                recommended: ExperiencePolicy.recommended,
                tier: Hardware.tier,
                cpu: Hardware.cpuModel,
                threads: Hardware.cpuThreads,
                memGiB: Number(Hardware.memGiB.toFixed(1)),
                gpus: Hardware.gpus.map(g => g.label),
                palette: Palette.live ? "theme" : "fallback",
                panels: PanelRouter.openPanels,
                launchTime: Quickshell.launchTime
            });
        }
    }
}
