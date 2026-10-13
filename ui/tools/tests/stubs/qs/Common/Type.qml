pragma Singleton
import QtQuick
// test stand-in for Common/Type: the shell's faces are whatever the test machine has
QtObject {
    property string ui: Qt.application.font.family
    property string display: Qt.application.font.family
    property string mono: "monospace"
    property string icons: Qt.application.font.family
    readonly property int micro: 10
    readonly property int caption: 11
    readonly property int label: 12
    readonly property int body: 14
    readonly property int title: 16
    readonly property int headline: 20
    readonly property int data: 14
    readonly property int displayXL: 40
    readonly property real tracking: 0
    readonly property real dataTracking: 0
    readonly property bool tabular: false
}
