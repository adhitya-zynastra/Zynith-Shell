pragma Singleton
import QtQuick
// test stand-in for Services/Material: a backdrop that a test can switch off
QtObject {
    property bool blur: true
    property real fillAlpha: 0.44
}
