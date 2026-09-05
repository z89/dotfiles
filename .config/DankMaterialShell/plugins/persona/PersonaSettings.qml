import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "persona"

    StyledText {
        width: parent.width
        text: "Persona"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Shows the same profile picture DMS uses on the lock screen and in the control centre. Set or change it with `avatar-make <photo>` in a terminal, or from Settings > Profile. A picture with a transparent background picks up the theme colour behind it."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    SelectionSetting {
        settingKey: "ringColor"
        label: "Ring colour"
        description: "Theme colour drawn around the picture"
        options: [
            { label: "Primary", value: "primary" },
            { label: "Secondary", value: "secondary" },
            { label: "Tertiary", value: "tertiary" },
            { label: "Outline", value: "outline" },
            { label: "None", value: "none" }
        ]
        defaultValue: "primary"
    }

    SliderSetting {
        settingKey: "ringWidth"
        label: "Ring width"
        description: "Thickness of the ring in pixels"
        defaultValue: 2
        minimum: 0
        maximum: 4
        unit: "px"
    }

    SliderSetting {
        settingKey: "inset"
        label: "Inset"
        description: "Space between the avatar and the bar edge. Smaller means a bigger avatar."
        defaultValue: 3
        minimum: 0
        maximum: 8
        unit: "px"
    }

    ToggleSetting {
        settingKey: "themedBackdrop"
        label: "Themed backdrop"
        description: "Fill behind the picture with the primary container colour instead of a neutral surface"
        defaultValue: true
    }

    SelectionSetting {
        settingKey: "clickAction"
        label: "Left click"
        description: "What the avatar opens"
        options: [
            { label: "User panel", value: "popout" },
            { label: "Control centre", value: "controlcenter" },
            { label: "Dash", value: "dash" },
            { label: "Power menu", value: "powermenu" },
            { label: "Lock screen", value: "lock" }
        ]
        defaultValue: "popout"
    }

    SelectionSetting {
        settingKey: "rightClickAction"
        label: "Right click"
        description: "Secondary action"
        options: [
            { label: "Power menu", value: "powermenu" },
            { label: "Control centre", value: "controlcenter" },
            { label: "Lock screen", value: "lock" },
            { label: "Nothing", value: "none" }
        ]
        defaultValue: "powermenu"
    }
}
