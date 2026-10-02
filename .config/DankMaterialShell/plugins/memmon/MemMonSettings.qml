import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "memmon"

    StyledText {
        width: parent.width
        text: "Memory Monitor"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Shows RAM as a percentage and as GB used out of the total. Hovering or clicking opens the process list sorted by memory."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    ToggleSetting {
        settingKey: "showPercent"
        label: "Show percentage"
        description: "Print the share of RAM in use before the GB figures"
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "showGb"
        label: "Show GB used of total"
        description: "Print used and total RAM in GB, for example 10.6/33.1 GB"
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "minimumWidth"
        label: "Fixed width"
        description: "Reserve room for the widest value so the bar does not shift as the number changes"
        defaultValue: false
    }
}
