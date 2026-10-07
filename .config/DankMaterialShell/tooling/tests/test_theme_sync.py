"""Headless integration checks for the patched shell theme contract.

Set DMS_THEME_TEST_SOURCE to an unwatched copy of the embedded shell source.
"""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


TOOLING = Path(__file__).resolve().parents[1]
PATCHER = TOOLING / "bin/dms-shell-patch"
PATCH_DIR = TOOLING.parent / "patches"
SHIM = TOOLING / "shim/dms"
SOURCE = os.environ.get("DMS_THEME_TEST_SOURCE")


@unittest.skipUnless(SOURCE and Path(SOURCE).is_dir(), "set DMS_THEME_TEST_SOURCE")
class ThemeSyncBuildTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="dms-theme-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / "source"
        shutil.copytree(SOURCE, self.source)
        self.output = self.root / "output"

    def build(self):
        env = os.environ.copy()
        env.update({
            "DMS_SHELL_SRC": str(self.source),
            "DMS_SHELL_PATCHED": str(self.output),
            "DMS_PATCH_DIR": str(PATCH_DIR),
            "DMS_NO_NOTIFY": "1",
            "THEME_SYNC": "1",
        })
        return subprocess.run([str(PATCHER)], env=env, text=True, capture_output=True)

    def test_theme_contract_and_selected_core_binary(self):
        result = self.build()
        self.assertEqual(result.returncode, 0, result.stderr)
        theme = (self.output / "Common/Theme.qml").read_text()
        wallpaper = (self.output / "Modules/WallpaperBackground.qml").read_text()
        bar = (self.output / "Modules/DankBar/DankBarWindow.qml").read_text()
        for marker in (
            "wallpapersDecoding", "colorFadeMs: 500", "paletteHeld",
            "paletteRegenerating", "consumerReady", "maybeReleasePalette",
            "paletteStamped", "paletteStampPending", "snapshotsPending",
            '"/scripts/dms-matugen-thumb"', "Proc.dmsBin",
        ):
            self.assertIn(marker, theme)
        for marker in ("paletteLanded", "decodingForPalette", "colorSyncHold", "clearPaletteWait"):
            self.assertIn(marker, wallpaper)
        self.assertIn("onFrameSwapped", bar)

        helper = self.output / "scripts/dms-matugen-thumb"
        selected = self.root / "selected-dms"
        selected.write_text('#!/bin/sh\nprintf "%s\\n" "$@" > "$DMS_TEST_ARGS"\n')
        selected.chmod(0o755)
        stock_dir = self.root / "stock-bin"
        stock_dir.mkdir()
        stock = stock_dir / "dms"
        stock.write_text("#!/bin/sh\nexit 99\n")
        stock.chmod(0o755)
        magick = stock_dir / "magick"
        magick.write_text('#!/bin/sh\nfor arg; do out=$arg; done\nprintf thumb > "$out"\n')
        magick.chmod(0o755)
        wallpaper_file = self.root / "image.jpg"
        wallpaper_file.write_bytes(b"image")
        args_file = self.root / "args"
        env = os.environ.copy()
        env["PATH"] = str(stock_dir) + os.pathsep + env["PATH"]
        env["XDG_CACHE_HOME"] = str(self.root / "cache")
        env["DMS_TEST_ARGS"] = str(args_file)
        call = subprocess.run(
            [str(helper), str(selected), "matugen", "queue", "--kind", "image", "--value", str(wallpaper_file)],
            env=env, text=True, capture_output=True,
        )
        self.assertEqual(call.returncode, 0, call.stderr)
        passed = args_file.read_text().splitlines()
        self.assertEqual(passed[:5], ["matugen", "queue", "--kind", "image", "--value"])
        self.assertNotEqual(passed[5], str(wallpaper_file))
        self.assertTrue(Path(passed[5]).is_file())
        env["DMS_PATCHED_BINARY"] = str(selected)
        env["DMS_SHELL_DIR"] = str(self.output)
        shim_call = subprocess.run(
            [str(SHIM), "matugen", "queue", "--kind", "image", "--value", str(wallpaper_file)],
            env=env, text=True, capture_output=True,
        )
        self.assertEqual(shim_call.returncode, 0, shim_call.stderr)
        self.assertEqual(args_file.read_text().splitlines(), passed)
        cached_call = subprocess.run(
            [str(SHIM), "matugen", "queue", "--kind", "image", "--value", passed[5]],
            env=env, text=True, capture_output=True,
        )
        self.assertEqual(cached_call.returncode, 0, cached_call.stderr)
        self.assertEqual(args_file.read_text().splitlines(), passed)
        magick.write_text("#!/bin/sh\nexit 1\n")
        failed_thumbnail = self.root / "another.jpg"
        failed_thumbnail.write_bytes(b"another image")
        fallback_call = subprocess.run(
            [str(SHIM), "matugen", "queue", "--value", str(failed_thumbnail)],
            env=env, text=True, capture_output=True,
        )
        self.assertEqual(fallback_call.returncode, 0, fallback_call.stderr)
        self.assertEqual(args_file.read_text().splitlines(), ["matugen", "queue", "--value", str(failed_thumbnail)])
        missing = subprocess.run(
            [str(helper), "dms", "matugen", "queue"], env=env, text=True, capture_output=True,
        )
        self.assertNotEqual(missing.returncode, 0)

    def test_changed_theme_anchor_keeps_existing_output(self):
        target = self.source / "Common/Theme.qml"
        text = target.read_text()
        old = 'const args = [Proc.dmsBin, "matugen", "queue",'
        self.assertIn(old, text)
        target.write_text(text.replace(old, 'const args = [Proc.newBin, "matugen", "queue",', 1))
        self.output.mkdir()
        sentinel = self.output / "keep"
        sentinel.write_text("previous build")
        result = self.build()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("required theme sync incompatible", result.stderr)
        self.assertEqual(sentinel.read_text(), "previous build")
        self.assertFalse((self.output / "Common/Theme.qml").exists())

    def test_damaged_network_fix_is_rejected(self):
        target = self.source / "Services/DMSNetworkService.qml"
        text = target.read_text()
        old = "WifiDeviceState.completed(state, pendingConnectionSSID, pendingConnectionDevice)"
        self.assertIn(old, text)
        target.write_text(text.replace(old, "false", 1))
        result = self.build()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("network patch incompatible", result.stderr)
        self.assertFalse(self.output.exists())

    def test_unrelated_upstream_network_addition_is_accepted(self):
        target = self.source / "Services/DMSNetworkService.qml"
        text = target.read_text()
        anchor = "    property bool networkAvailable: false\n"
        self.assertIn(anchor, text)
        target.write_text(text.replace(anchor, anchor + "    property bool futureCellularMetric: false\n", 1))
        result = self.build()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("futureCellularMetric", (self.output / "Services/DMSNetworkService.qml").read_text())


if __name__ == "__main__":
    unittest.main()
