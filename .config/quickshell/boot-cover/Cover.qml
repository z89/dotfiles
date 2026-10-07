// boot-cover: one screen's copy of the plymouth dank-unlock frame (two-step module).
// Background stretched to the whole screen (ScaleBackgroundImage=true), watermark at
// plymouth's own position, truncated to whole pixels as plymouth does:
//   x = (W - w) * 0.5, y = (H - h) * 0.40
// The throbber is not reproduced. Pure QtQuick so selftest.sh can render it headless.

import QtQuick

Item {
    id: cover

    // theme directory (plymouth ImageDir); empty means flat colour only
    property string themeDir: ""
    // plymouth BackgroundStartColor, also shown wherever an image is missing
    property color fallbackColor: "#1d1013"
    readonly property real watermarkXAlign: 0.5
    readonly property real watermarkYAlign: 0.40
    readonly property bool backgroundReady: background.status === Image.Ready
    readonly property bool watermarkReady: watermark.status === Image.Ready

    Rectangle {
        anchors.fill: parent
        color: cover.fallbackColor
    }

    Image {
        id: background

        anchors.fill: parent
        source: cover.themeDir !== "" ? "file://" + cover.themeDir + "/background.png" : ""
        fillMode: Image.Stretch
        asynchronous: false
        cache: false
        smooth: true
        visible: status === Image.Ready
    }

    Image {
        id: watermark

        source: cover.themeDir !== "" ? "file://" + cover.themeDir + "/watermark.png" : ""
        asynchronous: false
        cache: false
        smooth: false
        width: implicitWidth
        height: implicitHeight
        x: Math.floor((cover.width - width) * cover.watermarkXAlign)
        y: Math.floor((cover.height - height) * cover.watermarkYAlign)
        visible: status === Image.Ready
    }
}
