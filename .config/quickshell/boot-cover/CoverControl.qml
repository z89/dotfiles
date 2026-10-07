// boot-cover timing: flag polling cadence, --test hold, the 400ms fade and the hard
// deadline. Pure QtQuick so selftest.sh can drive it headless; shell.qml wires the
// flag file to flagSeen() and quitRequested to Qt.quit().

import QtQuick

QtObject {
    id: ctl

    // --test: hold for holdMs, then fade, ignoring the flag
    property bool testMode: false
    property int holdMs: 3000
    property int pollMs: 50
    property int fadeMs: 400
    readonly property real startMs: Date.now()
    // absolute epoch ms by which the process must be gone (launcher start + 14.5s)
    property real deadlineMs: ctl.startMs + 14500

    // shared by every screen so all monitors fade in lockstep
    property real coverOpacity: 1
    property bool fading: false
    // true when the flag already existed at the first check: hide and quit at once
    property bool skip: false
    property int polls: 0
    property bool quitting: false

    signal pollRequested
    signal quitRequested

    function flagSeen() {
        if (ctl.testMode || ctl.fading || ctl.skip || ctl.quitting)
            return;
        if (ctl.polls <= 1) {
            ctl.skip = true;
            ctl.finish();
        } else {
            ctl.fadeOut();
        }
    }

    function fadeOut() {
        if (ctl.fading || ctl.skip || ctl.quitting)
            return;
        ctl.fading = true;
        fadeAnim.start();
    }

    function finish() {
        if (ctl.quitting)
            return;
        ctl.quitting = true;
        ctl.quitRequested();
    }

    property Timer pollTimer: Timer {
        interval: ctl.pollMs
        repeat: true
        triggeredOnStart: true
        running: !ctl.testMode && !ctl.fading && !ctl.skip && !ctl.quitting
        onTriggered: {
            ctl.polls += 1;
            ctl.pollRequested();
        }
    }

    property Timer holdTimer: Timer {
        interval: ctl.holdMs
        running: ctl.testMode
        onTriggered: ctl.fadeOut()
    }

    // self-destruct, independent of the flag: start the fade in time to finish by
    // the deadline, and quit at the deadline whatever state the fade is in
    property Timer deadlineFadeTimer: Timer {
        interval: Math.max(0, ctl.deadlineMs - ctl.fadeMs - ctl.startMs)
        running: true
        onTriggered: ctl.fadeOut()
    }

    property Timer deadlineQuitTimer: Timer {
        interval: Math.max(1, ctl.deadlineMs - ctl.startMs)
        running: true
        onTriggered: ctl.finish()
    }

    property NumberAnimation fadeAnim: NumberAnimation {
        id: fadeAnim

        target: ctl
        property: "coverOpacity"
        from: 1
        to: 0
        duration: ctl.fadeMs
        easing.type: Easing.OutCubic
        onFinished: ctl.finish()
    }
}
