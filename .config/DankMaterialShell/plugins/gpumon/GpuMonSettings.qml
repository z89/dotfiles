import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "gpumon"

    StyledText {
        width: parent.width
        text: "GPU Monitor"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Reads gpu_busy_percent and the VRAM counters from the first amdgpu card in /sys/class/drm."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    ToggleSetting {
        settingKey: "showVram"
        label: "Show VRAM"
        description: "Print VRAM in use next to the utilisation"
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "vramInGb"
        label: "VRAM in GB"
        description: "Show VRAM as GB used out of the total, for example 4.6/8.6 GB, instead of a percentage"
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "showTemp"
        label: "Show temperature"
        description: "Print the GPU edge temperature after the VRAM"
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "minimumWidth"
        label: "Fixed width"
        description: "Reserve room for the widest value so the bar does not shift as the number changes"
        defaultValue: false
    }

    SliderSetting {
        settingKey: "interval"
        label: "Update interval"
        description: "How often the counters are read"
        defaultValue: 2000
        minimum: 500
        maximum: 10000
        unit: "ms"
    }
}
