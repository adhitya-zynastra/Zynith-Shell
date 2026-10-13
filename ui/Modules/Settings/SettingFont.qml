import QtQuick
import qs.Common
import qs.Components

// A font family, picked from the installed ones (Components/FontPicker). Empty: the default named in `fallback`.
SettingRow {
    id: root
    property string fallback: "The default"
    controlWidth: 300

    FontPicker {
        width: parent.width
        value: root.value ?? ""
        fallback: root.fallback
        onPicked: family => {
            if (family === "")
                Config.reset(root.domain, root.key);
            else
                root.write(family);
        }
    }
}
