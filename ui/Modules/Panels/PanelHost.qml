import QtQuick
import Quickshell
import qs.Services

// One panel layer per output. Windows exist only while a panel is open or closing on that output.
Scope {
    Variants {
        model: Quickshell.screens

        delegate: PanelLayer {}
    }
}
