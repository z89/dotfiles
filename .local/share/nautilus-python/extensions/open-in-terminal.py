"""
Nautilus extension: "Open in Terminal" context menu action.

Adds a right-click menu item that opens kitty in the selected directory
(or the current folder if right-clicking the background).
"""

import os
import subprocess
import traceback

import gi

gi.require_version("Nautilus", "4.1")
gi.require_version("Gtk", "4.0")

from gi.repository import GObject, Nautilus
from urllib.parse import unquote, urlparse


def _get_path(file_info):
    """Extract a local filesystem path from a NautilusFileInfo."""
    uri = file_info.get_uri()
    parsed = urlparse(uri)
    if parsed.scheme == "file":
        return unquote(parsed.path)
    return None


_LOG = os.path.expanduser("~/.local/share/nautilus-python/open-in-terminal.log")


def _open_terminal(path):
    # start_new_session detaches from Nautilus's process group so the terminal
    # survives Nautilus closing; errors are logged because Nautilus silently
    # swallows exceptions raised inside menu-item callbacks.
    try:
        subprocess.Popen(
            ["kitty", "--detach", "--directory", path],
            start_new_session=True,
        )
    except Exception:
        with open(_LOG, "a") as fh:
            fh.write(f"failed to open terminal in {path!r}:\n")
            fh.write(traceback.format_exc())
        raise


class OpenInTerminal(GObject.GObject, Nautilus.MenuProvider):
    def get_file_items(self, files):
        # Only show for single directory selection
        if len(files) != 1:
            return []
        f = files[0]
        if not f.is_directory():
            return []
        path = _get_path(f)
        if not path:
            return []

        item = Nautilus.MenuItem(
            name="OpenInTerminal::open_folder",
            label="Open in Terminal",
            tip="Open this folder in kitty",
        )
        item.connect("activate", lambda _w, p=path: _open_terminal(p))
        return [item]

    def get_background_items(self, folder):
        path = _get_path(folder)
        if not path:
            return []

        item = Nautilus.MenuItem(
            name="OpenInTerminal::open_bg",
            label="Open in Terminal",
            tip="Open terminal here",
        )
        item.connect("activate", lambda _w, p=path: _open_terminal(p))
        return [item]
