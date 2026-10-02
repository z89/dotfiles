import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

// Memory Monitor: RAM as a percentage plus GB used out of the total, in a
// DankBar pill that matches the stock memUsage pill (icon, sizes, level
// colours, and the click that opens the process list sorted by memory).
PluginComponent {
    id: root

    readonly property bool showPercent: pluginData.showPercent !== undefined ? pluginData.showPercent : true
    readonly property bool showGb: pluginData.showGb !== undefined ? pluginData.showGb : true
    readonly property bool minimumWidth: pluginData.minimumWidth !== undefined ? pluginData.minimumWidth : false

    readonly property real usage: DgopService.memoryUsage
    readonly property real usedGb: DgopService.usedMemoryKB * 1024 / 1e9
    readonly property real totalGb: DgopService.totalMemoryKB * 1024 / 1e9
    readonly property real textSize: Theme.barTextSize(barThickness, barConfig?.fontScale, barConfig?.maximizeWidgetText)
    readonly property color levelColor: {
        if (usage > 90)
            return Theme.tempDanger;
        if (usage > 75)
            return Theme.tempWarning;
        return Theme.widgetIconColor;
    }

    readonly property string percentText: usage ? usage.toFixed(0) + "%" : "--%"
    readonly property string gbText: totalGb > 0 ? usedGb.toFixed(1) + "/" + totalGb.toFixed(1) + " GB" : "--/-- GB"
    readonly property string gbReserve: "88.8/" + (totalGb > 0 ? totalGb.toFixed(1) : "88.8") + " GB"

    Ref {
        service: DgopService
        modules: ["memory"]
        active: root.effectiveVisible
    }

    // Opens DMS's own process list through PopoutManager, the same path the
    // stock pills take, so it follows the hover-to-open setting: a hover
    // request closes again when the pointer leaves, a click pins it.
    property int _openRetries: 0

    function openProcessList(hover) {
        DgopService.setSortBy("memory");
        const loader = PopoutService.processListPopoutLoader;
        if (loader)
            loader.active = true;
        const popout = PopoutService.processListPopout;
        if (!popout) {
            if (_openRetries++ < 10)
                Qt.callLater(() => openProcessList(hover));
            return;
        }
        _openRetries = 0;
        surfaceContext?.ensureVisible(root);
        if (!surfaceContext?.positionPopout(popout, root, section))
            return;
        if (typeof popout.prepareForTrigger === "function")
            popout.prepareForTrigger("memory", hover ? "hover" : "click");
        if (hover)
            PopoutManager.requestHoverPopout(popout, undefined, "memory");
        else
            PopoutManager.requestPopout(popout, undefined, "memory");
    }

    function triggerHoverPopout(widgetHostId) {
        openProcessList(true);
    }

    pillClickAction: () => openProcessList(false)

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            DankIcon {
                name: "developer_board"
                size: root.iconSizeLarge
                color: root.levelColor
                anchors.verticalCenter: parent.verticalCenter
            }

            // The figures sit tight against the icon. With fixed width on,
            // the spare room goes after them instead of around them.
            Item {
                readonly property real packedWidth: (percentLabel.visible ? percentLabel.reservedWidth : 0) + (gbLabel.visible ? figures.spacing + gbLabel.reservedWidth : 0)
                implicitWidth: root.minimumWidth ? Math.ceil(Math.max(figures.implicitWidth, packedWidth)) : figures.implicitWidth
                implicitHeight: figures.implicitHeight
                anchors.verticalCenter: parent.verticalCenter

                Row {
                    id: figures
                    spacing: Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter

                    NumericText {
                        id: percentLabel
                        visible: root.showPercent || !root.showGb
                        isMonospace: false
                        font.features: ({
                                "tnum": 1
                            })
                        text: root.percentText
                        reserveText: "100%"
                        font.pixelSize: root.textSize
                        color: Theme.widgetTextColor
                    }

                    NumericText {
                        id: gbLabel
                        visible: root.showGb
                        isMonospace: false
                        font.features: ({
                                "tnum": 1
                            })
                        text: root.gbText
                        reserveText: root.gbReserve
                        font.pixelSize: root.textSize
                        color: Theme.widgetTextColor
                    }
                }
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXS

            DankIcon {
                name: "developer_board"
                size: root.iconSizeLarge
                color: root.levelColor
                anchors.horizontalCenter: parent.horizontalCenter
            }

            NumericText {
                isMonospace: false
                font.features: ({
                        "tnum": 1
                    })
                text: root.usage ? root.usage.toFixed(0) : "--"
                font.pixelSize: root.textSize
                color: Theme.widgetTextColor
                anchors.horizontalCenter: parent.horizontalCenter
            }

            NumericText {
                isMonospace: false
                visible: root.showGb
                text: root.totalGb > 0 ? root.usedGb.toFixed(1) : "--"
                font.pixelSize: root.textSize
                color: Theme.surfaceVariantText
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }
}
