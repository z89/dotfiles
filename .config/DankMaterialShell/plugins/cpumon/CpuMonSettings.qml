import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "cpumon"

    StyledText {
        width: parent.width
        text: "CPU Monitor"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Shows CPU utilisation and temperature in one pill. Hovering or clicking opens the process list sorted by CPU."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    ToggleSetting {
        settingKey: "showTemp"
        label: "Show temperature"
        description: "Print the CPU package temperature after the utilisation"
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "minimumWidth"
        label: "Fixed width"
        description: "Reserve room for the widest value so the bar does not shift as the number changes"
        defaultValue: false
    }
}
