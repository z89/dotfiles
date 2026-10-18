"""Headless checks for autostart workspace urgency and its patch anchor."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


TOOLING = Path(__file__).resolve().parents[1]
PATCHER = TOOLING / "bin/dms-shell-patch"
HYPR_CONFIG = TOOLING.parents[1] / "hypr/hyprland.lua"
PATCH = PATCHER.read_text().split("<<'PYSTARTUP'\n", 1)[1].split("\nPYSTARTUP\n", 1)[0]
SOURCE = os.environ.get("DMS_THEME_TEST_SOURCE")


class StartupUrgencyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.target = self.root / "Services/CompositorService.qml"
        self.target.parent.mkdir()
        if SOURCE:
            self.target.write_text((Path(SOURCE) / "Services/CompositorService.qml").read_text())
        else:
            self.target.write_text("""    function workspaceUrgent(record, loadedUrgent) {
        switch (compositor) {
        default:
            return record?.urgent === true;
        }
    }
""")

    def patch(self):
        return subprocess.run(
            ["python3", "-", str(self.root)], input=PATCH,
            text=True, capture_output=True,
        )

    def test_startup_alerts_resume_after_focus_and_preserve_other_windows(self):
        patched = self.patch()
        self.assertEqual(patched.returncode, 0, patched.stderr)
        text = self.target.read_text()
        function = text.split("    function startupWorkspaceUrgent(record) {", 1)[1]
        function = "function startupWorkspaceUrgent(record) {" + function.split(
            "    function workspaceUrgent(record, loadedUrgent)", 1
        )[0]
        script = function + """
const assert = require('node:assert/strict');
const Hyprland = {toplevels: {values: []}};
const workspace = {id: 9, urgent: true};
const startup = {
    workspace: {id: 9}, urgent: true,
    lastIpcObject: {tags: ['startup-quiet'], focusHistoryID: 4}
};
Hyprland.toplevels.values = [startup];
assert.equal(startupWorkspaceUrgent(workspace), false, 'quiet before first focus');
startup.lastIpcObject.focusHistoryID = 0;
assert.equal(startupWorkspaceUrgent(workspace), false, 'history index cannot prove first focus');
delete startup.lastIpcObject.focusHistoryID;
assert.equal(startupWorkspaceUrgent(workspace), false, 'static tag needs no history index');
startup.lastIpcObject.tags = [];
assert.equal(startupWorkspaceUrgent(workspace), true, 'alerts resume after focus');
assert.equal(startupWorkspaceUrgent(workspace), true, 'alerts remain after leaving');
startup.lastIpcObject.tags = ['startup-quiet'];
const manual = {
    workspace: {id: 9}, urgent: true,
    lastIpcObject: {tags: [], focusHistoryID: -1}
};
Hyprland.toplevels.values.push(manual);
assert.equal(startupWorkspaceUrgent(workspace), true, 'other urgent window still alerts');
manual.urgent = false;
assert.equal(startupWorkspaceUrgent(workspace), false, 'nonurgent sibling does not alert');
manual.urgent = true;
manual.workspace.id = 10;
assert.equal(startupWorkspaceUrgent(workspace), false, 'other workspace is independent');
assert.equal(startupWorkspaceUrgent({id: 10, urgent: true}), true, 'manual launch alerts');
delete startup.lastIpcObject;
assert.equal(startupWorkspaceUrgent(workspace), true, 'unknown metadata preserves alert');
Hyprland.toplevels.values = [];
assert.equal(startupWorkspaceUrgent(workspace), true, 'unknown windows preserve alert');
assert.equal(startupWorkspaceUrgent({id: 9, urgent: false}), false, 'no invented alert');
assert.equal(startupWorkspaceUrgent(null), false, 'missing workspace');
"""
        result = subprocess.run(["node", "-"], input=script, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('case "hyprland":\n            return startupWorkspaceUrgent(record);', text)

    def test_hyprland_handlers_preserve_pending_apps_across_startup_reloads(self):
        config = HYPR_CONFIG.read_text().split("---- AUTOSTART ----", 1)[1]
        config = config.split("---- ENVIRONMENT VARIABLES ----", 1)[0]
        script = '''
local handlers, windows, launches = {}, {}, {}
local local_conf = { autostart = { "local-command" } }
local hl = {
    on = function(event, fn) handlers[event] = fn end,
    exec_cmd = function(command, rules)
        assert(rules == nil, "startup must not depend on exec rule inheritance")
        launches[#launches + 1] = command
    end,
    dsp = { window = { tag = function(spec) return spec end } },
    dispatch = function(spec)
        local address = assert(spec.window:match("^address:(.+)$"))
        local window = assert(windows[address])
        local name = spec.tag:sub(2)
        window.tags[name] = spec.tag:sub(1, 1) == "+" or nil
    end,
    get_windows = function(filter)
        assert(filter.tag == "startup-quiet")
        local found = {}
        for _, window in pairs(windows) do
            if window.tags[filter.tag] then found[#found + 1] = window end
        end
        return found
    end,
}
'''
        script += config + '''
local function opened(address, class, active)
    local window = { address = address, class = class, active = active, tags = {} }
    windows[address] = window
    handlers["window.open"](window)
    return window
end
local early = opened("0x0", "spotify", false)
assert(not early.tags["startup-quiet"], "loading config must not arm startup")
handlers["hyprland.start"]()
assert(#launches == 6, "existing startup commands must remain registered")
'''
        # DMS regenerates layout and reloads the config before the gate releases
        # these apps. Re-evaluate the real config with new locals and callbacks.
        script += config + config + '''
-- Windows arrive after the gate and any Electron process handoff, without a
-- launch rule or timer. The open event must provide the static tag itself.
local mullvad = opened("0x1", "mullvad-vpn", false)
local spotify = opened("0x2", "Spotify", false)
local spotify_extra = opened("0x3", "", false)
assert(not spotify_extra.tags["startup-quiet"])
spotify_extra.class = "spotify"
handlers["window.class"](spotify_extra)
local other = opened("0x4", "kitty", false)
assert(mullvad.tags["startup-quiet"])
assert(spotify.tags["startup-quiet"])
assert(spotify_extra.tags["startup-quiet"])
assert(not other.tags["startup-quiet"])
handlers["window.active"](other)
assert(mullvad.tags["startup-quiet"] and spotify.tags["startup-quiet"])
handlers["window.active"](mullvad)
assert(not mullvad.tags["startup-quiet"], "first focus must restore Mullvad alerts")
assert(spotify.tags["startup-quiet"], "Spotify is independent")
'''
        script += config + '''
local manual_mullvad = opened("0x5", "Mullvad VPN", false)
assert(not manual_mullvad.tags["startup-quiet"], "later launches must alert normally")
handlers["window.active"](spotify)
assert(not spotify.tags["startup-quiet"] and not spotify_extra.tags["startup-quiet"])
handlers["window.active"](spotify)
assert(not spotify.tags["startup-quiet"], "leaving and returning must not rearm suppression")
local manual_spotify = opened("0x6", "spotify", false)
assert(not manual_spotify.tags["startup-quiet"])
handlers["window.active"](nil)
-- A window that already received focus before its open callback needs no exception.
handlers["hyprland.start"]()
local active = opened("0x7", "spotify", true)
assert(not active.tags["startup-quiet"])
assert(not opened("0x8", "spotify", false).tags["startup-quiet"])
-- A config reload must not rearm startup, but must still remove existing tags.
local remaining = opened("0x9", "mullvad-vpn", false)
assert(remaining.tags["startup-quiet"])
'''
        script += config + '''
assert(not opened("0xa", "spotify", false).tags["startup-quiet"])
handlers["window.active"](remaining)
assert(not remaining.tags["startup-quiet"], "focus after config reload clears the old marker")
'''
        script += '''
handlers["hyprland.start"]()
local getenv = os.getenv
os.getenv = function(name)
    if name == "HYPRLAND_INSTANCE_SIGNATURE" then return "new-compositor" end
    return getenv(name)
end
'''
        script += config + '''
assert(not opened("0xb", "spotify", false).tags["startup-quiet"], "a new compositor cannot inherit pending state")
handlers["hyprland.start"]()
assert(opened("0xc", "spotify", false).tags["startup-quiet"], "a new startup arms its own exception")
'''
        result = subprocess.run(
            ["lua5.5", "-"], input=script, text=True, capture_output=True,
            env={**os.environ, "XDG_RUNTIME_DIR": str(self.root),
                 "HYPRLAND_INSTANCE_SIGNATURE": "startup-test"},
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_changed_anchor_fails_without_changing_source(self):
        original = self.target.read_text().replace(
            "function workspaceUrgent(record, loadedUrgent)",
            "function workspaceUrgent(record, loadedUrgent, changed)",
        )
        self.target.write_text(original)
        result = self.patch()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("refusing partial build", result.stderr)
        self.assertEqual(self.target.read_text(), original)


if __name__ == "__main__":
    unittest.main()
