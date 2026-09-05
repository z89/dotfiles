import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

// Persona: the user's profile picture as a DankBar pill.
//
// The picture is whatever DMS already knows about (PortalService.profileImage,
// backed by AccountsService), so the bar, the lock screen, the control centre
// header and the greeter all show the same image. Nothing is stored twice.
//
// Theme integration works in two layers:
//   * the ring around the picture is a live theme colour (primary by default)
//   * the disc behind the picture is a theme gradient, so a picture with a
//     transparent background (see avatar-make) is recoloured on every theme
//     switch without touching the file.
PluginComponent {
    id: root

    property var popoutService: null

    // ---- settings ----------------------------------------------------------

    readonly property string ringColorKey: pluginData.ringColor !== undefined ? pluginData.ringColor : "primary"
    readonly property int ringWidth: pluginData.ringWidth !== undefined ? pluginData.ringWidth : 2
    readonly property int inset: pluginData.inset !== undefined ? pluginData.inset : 3
    readonly property bool themedBackdrop: pluginData.themedBackdrop !== undefined ? pluginData.themedBackdrop : true
    readonly property string clickAction: pluginData.clickAction !== undefined ? pluginData.clickAction : "popout"
    readonly property string rightClickAction: pluginData.rightClickAction !== undefined ? pluginData.rightClickAction : "powermenu"

    readonly property color ringColor: {
        switch (ringColorKey) {
        case "secondary":
            return Theme.secondary;
        case "tertiary":
            return Theme.tertiary;
        case "outline":
            return Theme.outline;
        case "none":
            return "transparent";
        default:
            return Theme.primary;
        }
    }

    // ---- identity ----------------------------------------------------------

    readonly property string imagePath: PortalService.profileImage
    readonly property string imageUrl: {
        if (!imagePath || imagePath === "")
            return "";
        if (imagePath.startsWith("/"))
            return "file://" + imagePath;
        return imagePath;
    }

    readonly property string displayName: UserInfoService.fullName || UserInfoService.username || "User"

    readonly property string initials: {
        const name = (UserInfoService.fullName || UserInfoService.username || "").trim();
        if (!name)
            return "?";
        const parts = name.split(/\s+/).filter(p => p.length > 0);
        if (parts.length === 1)
            return parts[0].charAt(0).toUpperCase();
        return (parts[0].charAt(0) + parts[parts.length - 1].charAt(0)).toUpperCase();
    }

    readonly property string uptimeText: DgopService.uptime ? "up " + DgopService.uptime.slice(3) : ""

    // ---- actions -----------------------------------------------------------

    function runAction(name) {
        switch (name) {
        case "controlcenter":
            popoutService?.toggleControlCenter();
            break;
        case "dash":
            popoutService?.toggleDankDash("overview");
            break;
        case "notifications":
            popoutService?.toggleNotificationCenter();
            break;
        case "powermenu":
            popoutService?.togglePowerMenu();
            break;
        case "lock":
            Quickshell.execDetached(["dms", "ipc", "call", "lock", "lock"]);
            break;
        case "suspend":
            SessionService.suspend();
            break;
        default:
            break;
        }
    }

    pillClickAction: clickAction === "popout" ? null : () => root.runAction(root.clickAction)
    pillRightClickAction: rightClickAction === "none" ? null : () => root.runAction(root.rightClickAction)

    // ---- avatar ------------------------------------------------------------

    component Avatar: Item {
        id: av
        property int size: 24
        property int ring: root.ringWidth
        property bool hoverGrow: true
        readonly property bool hasImage: picture.status === Image.Ready

        width: size
        height: size
        scale: hoverGrow && hover.hovered ? 1.08 : 1.0

        Behavior on scale {
            NumberAnimation {
                duration: Theme.shortDuration
                easing.type: Theme.standardEasing
            }
        }

        HoverHandler {
            id: hover
        }

        Rectangle {
            id: ringRect
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            border.width: av.ring
            border.color: root.ringColor
            antialiasing: true

            Behavior on border.color {
                ColorAnimation {
                    duration: Theme.mediumDuration
                }
            }
        }

        // Theme backdrop. Shows through transparent regions of the picture and
        // behind the initials, so the avatar recolours with the theme.
        Rectangle {
            id: disc
            anchors.fill: parent
            anchors.margins: av.ring + 1
            radius: width / 2
            antialiasing: true
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop {
                    position: 0.0
                    color: root.themedBackdrop ? Qt.lighter(Theme.primaryContainer, 1.12) : Theme.surfaceContainerHigh
                }
                GradientStop {
                    position: 1.0
                    color: root.themedBackdrop ? Qt.darker(Theme.primaryContainer, 1.25) : Theme.surfaceContainerHigh
                }
            }
        }

        ClippingRectangle {
            anchors.fill: disc
            radius: width / 2
            color: "transparent"

            Image {
                id: picture
                anchors.fill: parent
                source: root.imageUrl
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                smooth: true
                mipmap: true
                cache: false
                sourceSize.width: 256
                sourceSize.height: 256
                visible: status === Image.Ready
            }
        }

        StyledText {
            anchors.centerIn: disc
            visible: !av.hasImage
            text: root.initials
            color: root.themedBackdrop ? Theme.surfaceText : Theme.widgetTextColor
            font.pixelSize: Math.max(8, Math.round(av.size * (root.initials.length > 1 ? 0.38 : 0.46)))
            font.weight: Font.DemiBold
        }
    }

    // ---- bar pills ---------------------------------------------------------

    horizontalBarPill: Component {
        Item {
            readonly property int avatarSize: Math.max(14, root.widgetThickness - root.inset * 2)
            implicitWidth: avatarSize
            implicitHeight: root.widgetThickness
            width: implicitWidth
            height: implicitHeight

            Avatar {
                anchors.centerIn: parent
                size: parent.avatarSize
            }
        }
    }

    verticalBarPill: Component {
        Item {
            readonly property int avatarSize: Math.max(14, root.widgetThickness - root.inset * 2)
            implicitWidth: root.widgetThickness
            implicitHeight: avatarSize
            width: implicitWidth
            height: implicitHeight

            Avatar {
                anchors.centerIn: parent
                size: parent.avatarSize
            }
        }
    }

    // ---- popout ------------------------------------------------------------

    popoutWidth: 340
    popoutHeight: 236

    popoutContent: Component {
        PopoutComponent {
            headerText: root.displayName
            detailsText: UserInfoService.username + "@" + UserInfoService.hostname + (root.uptimeText ? "  ·  " + root.uptimeText : "")
            showCloseButton: true

            Column {
                width: parent.width
                spacing: Theme.spacingM

                Row {
                    width: parent.width
                    spacing: Theme.spacingL

                    Avatar {
                        size: 72
                        ring: 3
                        hoverGrow: false
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spacingXS

                        StyledText {
                            text: root.displayName
                            font.pixelSize: Theme.fontSizeLarge
                            font.weight: Font.DemiBold
                            color: Theme.surfaceText
                        }

                        StyledText {
                            text: UserInfoService.username
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }

                        StyledText {
                            text: "Change the picture with avatar-make <photo>"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            visible: root.imageUrl === ""
                        }
                    }
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Theme.spacingL

                    Repeater {
                        model: [
                            { icon: "lock", label: "Lock", action: "lock" },
                            { icon: "bedtime", label: "Sleep", action: "suspend" },
                            { icon: "power_settings_new", label: "Power", action: "powermenu" },
                            { icon: "dashboard", label: "Dash", action: "dash" }
                        ]

                        delegate: Column {
                            required property var modelData
                            spacing: Theme.spacingXS

                            DankActionButton {
                                anchors.horizontalCenter: parent.horizontalCenter
                                iconName: modelData.icon
                                iconSize: 20
                                iconColor: Theme.surfaceText
                                backgroundColor: Theme.surfaceContainerHigh
                                buttonSize: 40
                                onClicked: root.runAction(modelData.action)
                            }

                            StyledText {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.label
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                            }
                        }
                    }
                }
            }
        }
    }
}
