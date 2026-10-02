import QtQuick
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

// GPU Monitor: GPU utilisation, VRAM and edge temperature as a DankBar pill that matches the stock
// cpuUsage and memUsage pills (same icon size, text size, level colours).
//
// dgop reports GPU names and temperatures but not utilisation, so this reads
// the amdgpu sysfs counters directly. The card is found once at startup.
PluginComponent {
    id: root

    readonly property bool showVram: pluginData.showVram !== undefined ? pluginData.showVram : true
    readonly property bool showTemp: pluginData.showTemp !== undefined ? pluginData.showTemp : true
    readonly property bool vramInGb: pluginData.vramInGb !== undefined ? pluginData.vramInGb : true
    readonly property bool minimumWidth: pluginData.minimumWidth !== undefined ? pluginData.minimumWidth : false
    readonly property int interval: pluginData.interval !== undefined ? pluginData.interval : 2000

    property string devicePath: ""
    property string tempPath: ""
    property int temperature: -1
    property int busy: -1
    property real vramUsed: 0
    property real vramTotal: 0

    readonly property real vramPercent: vramTotal > 0 ? vramUsed / vramTotal * 100 : 0
    readonly property real textSize: Theme.barTextSize(barThickness, barConfig?.fontScale, barConfig?.maximizeWidgetText)
    readonly property color levelColor: {
        if (busy > 80 || (showTemp && temperature > 85))
            return Theme.tempDanger;
        if (busy > 60 || (showTemp && temperature > 69))
            return Theme.tempWarning;
        return Theme.widgetIconColor;
    }

    readonly property string busyText: busy >= 0 ? busy + "%" : "--%"
    readonly property string tempText: temperature >= 0 ? temperature + "°" : "--°"
    readonly property string vramText: {
        if (vramTotal <= 0)
            return vramInGb ? "--/-- GB" : "--%";
        return vramInGb ? (vramUsed / 1e9).toFixed(1) + "/" + (vramTotal / 1e9).toFixed(1) + " GB" : vramPercent.toFixed(0) + "%";
    }
    readonly property string vramReserve: {
        if (!vramInGb)
            return "88%";
        const total = vramTotal > 0 ? (vramTotal / 1e9).toFixed(1) : "88.8";
        return "88.8/" + total + " GB";
    }

    Process {
        id: finder
        running: true
        // Prints the device directory, then its edge temperature sensor.
        command: ["sh", "-c", "for c in /sys/class/drm/card[0-9]*/device; do [ -r \"$c/gpu_busy_percent\" ] && { echo \"$c\"; ls -d \"$c\"/hwmon/hwmon*/temp1_input 2>/dev/null | head -n 1; exit 0; }; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                root.tempPath = lines[1] || "";
                root.devicePath = lines[0] || "";
            }
        }
    }

    FileView {
        id: busyFile
        path: root.devicePath ? root.devicePath + "/gpu_busy_percent" : ""
        onLoaded: {
            const v = parseInt(text());
            root.busy = isNaN(v) ? -1 : v;
        }
    }

    FileView {
        id: vramUsedFile
        path: root.devicePath && root.showVram ? root.devicePath + "/mem_info_vram_used" : ""
        onLoaded: root.vramUsed = parseFloat(text()) || 0
    }

    FileView {
        id: vramTotalFile
        path: root.devicePath && root.showVram ? root.devicePath + "/mem_info_vram_total" : ""
        onLoaded: root.vramTotal = parseFloat(text()) || 0
    }

    FileView {
        id: tempFile
        path: root.tempPath && root.showTemp ? root.tempPath : ""
        onLoaded: {
            const v = parseInt(text());
            root.temperature = isNaN(v) ? -1 : Math.round(v / 1000);
        }
    }

    Timer {
        interval: root.interval
        repeat: true
        triggeredOnStart: true
        running: root.devicePath !== "" && root.effectiveVisible
        onTriggered: {
            busyFile.reload();
            if (root.showVram)
                vramUsedFile.reload();
            if (root.showTemp && root.tempPath)
                tempFile.reload();
        }
    }

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            DankIcon {
                name: "videogame_asset"
                size: root.iconSizeLarge
                color: root.levelColor
                anchors.verticalCenter: parent.verticalCenter
            }

            // The figures sit tight against the icon. With fixed width on,
            // the spare room goes after them instead of around them.
            Item {
                readonly property real packedWidth: busyLabel.reservedWidth + (vramLabel.visible ? figures.spacing + vramLabel.reservedWidth : 0) + (tempLabel.visible ? figures.spacing + tempLabel.reservedWidth : 0)
                implicitWidth: root.minimumWidth ? Math.ceil(Math.max(figures.implicitWidth, packedWidth)) : figures.implicitWidth
                implicitHeight: figures.implicitHeight
                anchors.verticalCenter: parent.verticalCenter

                Row {
                    id: figures
                    spacing: Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter

                    NumericText {
                        id: busyLabel
                        isMonospace: false
                        font.features: ({
                                "tnum": 1
                            })
                        text: root.busyText
                        reserveText: "100%"
                        font.pixelSize: root.textSize
                        color: Theme.widgetTextColor
                    }

                    NumericText {
                        id: vramLabel
                        visible: root.showVram
                        isMonospace: false
                        font.features: ({
                                "tnum": 1
                            })
                        text: root.vramText
                        reserveText: root.vramReserve
                        font.pixelSize: root.textSize
                        color: Theme.widgetTextColor
                    }

                    NumericText {
                        id: tempLabel
                        visible: root.showTemp && root.tempPath !== ""
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
                name: "videogame_asset"
                size: root.iconSizeLarge
                color: root.levelColor
                anchors.horizontalCenter: parent.horizontalCenter
            }

            NumericText {
                isMonospace: false
                font.features: ({
                        "tnum": 1
                    })
                text: root.busy >= 0 ? String(root.busy) : "--"
                font.pixelSize: root.textSize
                color: Theme.widgetTextColor
                anchors.horizontalCenter: parent.horizontalCenter
            }

            NumericText {
                isMonospace: false
                visible: root.showVram
                text: root.vramTotal > 0 ? root.vramPercent.toFixed(0) : "--"
                font.pixelSize: root.textSize
                color: Theme.surfaceVariantText
                anchors.horizontalCenter: parent.horizontalCenter
            }

            NumericText {
                isMonospace: false
                visible: root.showTemp && root.tempPath !== ""
                text: root.temperature >= 0 ? root.temperature + "°" : "--"
                font.pixelSize: root.textSize
                color: Theme.surfaceVariantText
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }
}
