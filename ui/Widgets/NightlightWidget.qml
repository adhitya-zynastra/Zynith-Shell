import QtQuick
import qs.Common
import qs.Components
import qs.Services

// Night light from the native shell; state is read when the pointer arrives, so nothing polls.
BarItem {
    id: root

    onHoveredChanged: if (hovered)
        Core.refresh()
    Component.onCompleted: Core.refresh()
    onClicked: Core.toggleNightlight()

    Icon {
        name: "sunset-2"
        tone: Core.nightlight || Core.nightlightForced ? "accent" : "ink"
    }
}
