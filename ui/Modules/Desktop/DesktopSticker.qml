import QtQuick

Image {
    property var settings: ({})
    source: settings.image_path ? "file://" + settings.image_path : ""
    sourceSize.width: width * 2
    sourceSize.height: height * 2
    fillMode: Image.PreserveAspectFit
    asynchronous: true
    opacity: settings.opacity ?? 1
}
