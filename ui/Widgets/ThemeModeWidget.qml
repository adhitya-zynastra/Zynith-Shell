import QtQuick
import Quickshell
import qs.Common
import qs.Components
import qs.Services

// Light or dark: the palette's mode.
BarItem {
    id: root
    BarGlyph {
        item: root
        name: Scheme.mode === "light" ? "sun" : "moon"
    }
}
