import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

// CPU Monitor: CPU utilisation and temperature in one DankBar pill, laid out
// like the memmon and gpumon pills. The icon takes the warning colour when
// either the load or the temperature crosses the stock DMS thresholds.
PluginComponent {
    id: root

    readonly property bool showTemp: pluginData.showTemp !== undefined ? pluginData.showTemp : true
    readonly property bool minimumWidth: pluginData.minimumWidth !== undefined ? pluginData.minimumWidth : false

    readonly property real usage: DgopService.cpuUsage
    readonly property real temperature: DgopService.cpuTemperature
    readonly property bool hasTemp: temperature > 0
    readonly property real textSize: Theme.barTextSize(barThickness, barConfig?.fontScale, barConfig?.maximizeWidgetText)
    readonly property color levelColor: {
        if (usage > 80 || (showTemp && temperature > 85))
            return Theme.tempDanger;
        if (usage > 60 || (showTemp && temperature > 69))
            return Theme.tempWarning;
        return Theme.widgetIconColor;
    }

    readonly property string usageText: usage ? usage.toFixed(0) + "%" : "--%"
    readonly property string tempText: hasTemp ? Math.round(temperature) + "°" : "--°"

    Ref {
        service: DgopService
        modules: ["cpu"]
        active: root.effectiveVisible
    }

    // Opens DMS's own process list through PopoutManager, the same path the
    // stock pills take, so it follows the hover-to-open setting: a hover
    // request closes again when the pointer leaves, a click pins it.
    property int _openRetries: 0

    function openProcessList(hover) {
        DgopService.setSortBy("cpu");
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
            popout.prepareForTrigger("cpu", hover ? "hover" : "click");
        if (hover)
            PopoutManager.requestHoverPopout(popout, undefined, "cpu");
        else
            PopoutManager.requestPopout(popout, undefined, "cpu");
    }

    function triggerHoverPopout(widgetHostId) {
        openProcessList(true);
    }

    pillClickAction: () => openProcessList(false)

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            DankIcon {
                name: "memory"
                size: root.iconSizeLarge
                color: root.levelColor
                anchors.verticalCenter: parent.verticalCenter
            }

            Item {
                readonly property real packedWidth: usageLabel.reservedWidth + (tempLabel.visible ? figures.spacing + tempLabel.reservedWidth : 0)
                implicitWidth: root.minimumWidth ? Math.ceil(Math.max(figures.implicitWidth, packedWidth)) : figures.implicitWidth
                implicitHeight: figures.implicitHeight
                anchors.verticalCenter: parent.verticalCenter

                Row {
                    id: figures
                    spacing: Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter

                    NumericText {
                        id: usageLabel
                        isMonospace: false
                        font.features: ({
                                "tnum": 1
                            })
                        text: root.usageText
                        reserveText: "100%"
                        font.pixelSize: root.textSize
                        color: Theme.widgetTextColor
                    }

                    NumericText {
                        id: tempLabel
                        visible: root.showTemp
                        isMonospace: false
                        font.features: ({
                                "tnum": 1
                            })
                        text: root.tempText
                        reserveText: "88°"
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
                name: "memory"
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
                visible: root.showTemp
                text: root.hasTemp ? Math.round(root.temperature).toString() : "--"
                font.pixelSize: root.textSize
                color: Theme.surfaceVariantText
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }
}
