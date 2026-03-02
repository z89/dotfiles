#!/usr/bin/env python3
"""
Dynamic left/right gaps for ultrawide monitors.
- Floats new windows by default (only on creation, not on i3 reload).
- Adjusts left/right outer gaps based on tiled window count on the focused workspace.
- Persists inner/top/bottom gap changes across i3 reloads.
"""

import json
import os
import signal
import sys

import i3ipc

# Left/right gap (pixels each side) by tiled window count.
GAP_SCHEDULE = [
    (1, 680),  # 1-2 windows: ~20% margin
    (3, 340),  # 3-4 windows: ~10% margin
    (5, 154),  # 5+ windows:  ~3% margin
]

# Initial resize for specific window classes/instances.
WINDOW_SIZES_BY_INSTANCE = {
    "arch-assist-popup": "50ppt 40ppt",
}
WINDOW_SIZES_BY_CLASS = {
    "kitty": "1850 980",
}

# Gap state persistence.
STATE_FILE = os.path.expanduser("~/.config/i3/.gap-state.json")
DEFAULT_GAPS = {"inner": 30, "top": 30, "bottom": 30}

# Guard to suppress cascading window::floating events from our own float commands.
_suppress = False


def load_gap_state():
    try:
        with open(STATE_FILE) as f:
            return {**DEFAULT_GAPS, **json.load(f)}
    except (FileNotFoundError, json.JSONDecodeError):
        return dict(DEFAULT_GAPS)


def save_gap_state(state):
    with open(STATE_FILE, "w") as f:
        json.dump(state, f)


def get_gap(count):
    gap = GAP_SCHEDULE[0][1]
    for threshold, value in GAP_SCHEDULE:
        if count >= threshold:
            gap = value
    return gap


def update_gaps(i3, event=None):
    tree = i3.get_tree()
    focused = tree.find_focused()
    if focused is None:
        return

    ws = focused.workspace()
    if ws is None:
        return

    tiled = [
        w for w in ws.leaves()
        if not w.floating.startswith("auto_on") and not w.floating.startswith("user_on")
    ]
    gap = get_gap(len(tiled))
    i3.command(f"gaps left current set {gap}; gaps right current set {gap}")


def on_new_window(i3, event):
    """Float new windows by default and resize specific instances."""
    global _suppress
    con = event.container
    if con is None:
        return

    _suppress = True
    i3.command(f"[con_id={con.id}] floating enable")
    instance = con.window_instance or ""
    wm_class = con.window_class or ""
    if instance in WINDOW_SIZES_BY_INSTANCE:
        i3.command(f"[con_id={con.id}] resize set {WINDOW_SIZES_BY_INSTANCE[instance]}")
    elif wm_class in WINDOW_SIZES_BY_CLASS:
        i3.command(f"[con_id={con.id}] resize set {WINDOW_SIZES_BY_CLASS[wm_class]}")
    _suppress = False

    update_gaps(i3)


def on_floating_change(i3, event):
    """Update gaps when a window is toggled between floating/tiling."""
    if not _suppress:
        update_gaps(i3, event)


def adjust_gaps(i3, kind, delta):
    """Adjust a gap value by delta, save state, and apply."""
    state = load_gap_state()
    state[kind] = max(0, state[kind] + delta)
    save_gap_state(state)
    apply_gap_state(i3, state)


def apply_gap_state(i3, state=None):
    """Apply saved gap state for inner/top/bottom gaps."""
    if state is None:
        state = load_gap_state()
    i3.command(
        f"gaps inner all set {state['inner']}; "
        f"gaps top all set {state['top']}; "
        f"gaps bottom all set {state['bottom']}"
    )


def on_binding(i3, event):
    """Handle gap keybinds to persist changes."""
    cmd = event.binding.command
    if cmd.startswith("nop gap "):
        parts = cmd.split()
        # format: "nop gap <kind> <+/-> <amount>"
        kind = parts[2]    # inner, topbottom
        sign = parts[3]    # + or -
        amount = int(parts[4])
        delta = amount if sign == "+" else -amount
        if kind == "topbottom":
            adjust_gaps(i3, "top", delta)
            adjust_gaps(i3, "bottom", delta)
        else:
            adjust_gaps(i3, kind, delta)


# Clean shutdown on SIGTERM/SIGINT so exec_always restart is clean.
def handle_signal(signum, frame):
    sys.exit(0)

signal.signal(signal.SIGTERM, handle_signal)
signal.signal(signal.SIGINT, handle_signal)

i3 = i3ipc.Connection()

i3.on("window::new", on_new_window)
i3.on("window::close", update_gaps)
i3.on("window::move", update_gaps)
i3.on("window::floating", on_floating_change)
i3.on("window::focus", update_gaps)
i3.on("workspace::focus", update_gaps)
i3.on("binding", on_binding)

# Restore persisted gap state and update left/right gaps on startup.
apply_gap_state(i3)
update_gaps(i3)
i3.main()
