// boot-cover: one screen's copy of the plymouth dank-unlock frame (two-step module).
// Background stretched to the whole screen (ScaleBackgroundImage=true), watermark at
// plymouth's own position, truncated to whole pixels as plymouth does:
//   x = (W - w) * 0.5, y = (H - h) * 0.40
// The throbber plays plymouth's own throbber-NNNN.png frames at its spot:
//   x = 0.5 * W - w / 2, y = 0.52 * H - h / 2
// with the frame picked from the elapsed time modulo plymouth's 2s sequence. It starts on
// frame 0, right after the last frame plymouth leaves on screen. Pure QtQuick so
// selftest.sh can render it headless.

pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: cover

    // theme directory (plymouth ImageDir); empty means flat colour only
    property string themeDir: ""
    // plymouth BackgroundStartColor, also shown wherever an image is missing
    property color fallbackColor: "#1d1013"
    readonly property real watermarkXAlign: 0.5
    readonly property real watermarkYAlign: 0.40
    // HorizontalAlignment / VerticalAlignment and THROB_FRAMES in plymouth-dank-theme
    readonly property real throbberXAlign: 0.5
    readonly property real throbberYAlign: 0.52
    readonly property int throbberFrames: 60
    readonly property real throbberStartMs: Date.now()
    property int throbberFrame: 0
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

    // plymouth's throbber timer runs at 30 Hz
    Timer {
        interval: 33
        repeat: true
        running: cover.themeDir !== ""
        onTriggered: cover.throbberFrame = Math.floor(cover.throbberFrames * ((Date.now() - cover.throbberStartMs) % 2000) / 2000)
    }

    Repeater {
        model: cover.themeDir !== "" ? cover.throbberFrames : 0

        delegate: Image {
            id: throbberImage

            required property int index

            source: "file://" + cover.themeDir + "/throbber-" + String(throbberImage.index).padStart(4, "0") + ".png"
            asynchronous: false
            cache: false
            smooth: false
            width: implicitWidth
            height: implicitHeight
            x: Math.trunc(cover.width * cover.throbberXAlign - throbberImage.width / 2)
            y: Math.trunc(cover.height * cover.throbberYAlign - throbberImage.height / 2)
            visible: throbberImage.index === cover.throbberFrame && status === Image.Ready
        }
    }
}
