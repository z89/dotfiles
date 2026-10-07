// boot-cover: the plymouth frame redrawn on every monitor as an overlay layer, held until
// $XDG_RUNTIME_DIR/desktop-ready appears, then faded out over 400ms and quit.
// Started by ~/.local/bin/boot-cover (qs -n -c boot-cover), which passes:
//   BOOT_COVER_DIR          plymouth ImageDir (background.png, watermark.png), may be empty
//   BOOT_COVER_BG           plymouth BackgroundStartColor as #rrggbb
//   BOOT_COVER_FLAG         path of the desktop-ready flag
//   BOOT_COVER_DEADLINE_MS  epoch ms by which the process must have quit
//   BOOT_COVER_TEST=1       hold 3s, then fade, ignoring the flag
// Click-through (empty input mask), no keyboard focus, no exclusive zone. Hyprland's
// layer rule boot-cover-noanim removes the open animation, so the first frame is final.

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root

    readonly property string themeDir: root.envString("BOOT_COVER_DIR")
    readonly property color backgroundColour: /^#[0-9a-fA-F]{6}$/.test(root.envString("BOOT_COVER_BG")) ? root.envString("BOOT_COVER_BG") : "#1d1013"
    readonly property string flagPath: root.envString("BOOT_COVER_FLAG") !== "" ? root.envString("BOOT_COVER_FLAG") : root.envString("XDG_RUNTIME_DIR") + "/desktop-ready"

    function envString(name: string): string {
        const v = Quickshell.env(name);
        return (v === undefined || v === null) ? "" : String(v);
    }

    Component.onCompleted: Quickshell.watchFiles = false

    CoverControl {
        id: ctl

        testMode: root.envString("BOOT_COVER_TEST") === "1"
        deadlineMs: {
            const d = parseInt(root.envString("BOOT_COVER_DEADLINE_MS"), 10);
            const cap = ctl.startMs + 14500;
            return isNaN(d) ? cap : Math.min(d, cap);
        }
        onPollRequested: flag.reload()
        onQuitRequested: Qt.quit()
    }

    // Two independent ways of seeing the flag; whichever reports first triggers the fade
    // (flagSeen ignores every later call).
    // 1. FileView, polled every 50ms by CoverControl: a successful load means the flag is
    //    there. Loads are blocking, so a flag present at start is seen before any frame.
    //    Not proven for quickshell 0.3.1: that loaded fires for the zero-byte file `touch`
    //    makes, and that reload() picks up a path missing at first load. Hence path 2.
    FileView {
        id: flag

        path: ctl.testMode ? "" : root.flagPath
        blockLoading: true
        printErrors: false
        watchChanges: false
        onLoaded: ctl.flagSeen()
    }

    // 2. wait-flag.sh in a Process with a SplitParser on stdout (the pattern DMS uses
    //    throughout): a bash `test -e` loop every 50ms that prints "ready" and exits 0 when
    //    the flag exists, whatever its size, and exits 1 silently after 15s.
    Process {
        id: waiter

        command: ["/usr/bin/bash", Quickshell.shellDir + "/wait-flag.sh", root.flagPath, "15"]
        running: !ctl.testMode

        stdout: SplitParser {
            onRead: data => {
                if (data.trim() === "ready")
                    ctl.flagSeen();
            }
        }
    }

    Variants {
        model: Quickshell.screens

        delegate: PanelWindow {
            id: win

            required property var modelData

            screen: win.modelData
            visible: !ctl.skip
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            mask: Region {}

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "boot-cover"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            Cover {
                anchors.fill: parent
                opacity: ctl.coverOpacity
                themeDir: root.themeDir
                fallbackColor: root.backgroundColour
            }
        }
    }
}
