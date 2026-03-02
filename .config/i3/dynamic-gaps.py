#!/usr/bin/env python3
"""
Dynamic left/right gaps for ultrawide monitors.
- Floats new windows by default (only on creation, not on i3 reload).
- Adjusts left/right outer gaps based on tiled window count on the focused workspace.
"""

import i3ipc

# Left/right gap (pixels each side) by tiled window count.
GAP_SCHEDULE = [
    (1, 680),  # 1-2 windows: ~20% margin
    (3, 340),  # 3-4 windows: ~10% margin
    (5, 154),  # 5+ windows:  ~3% margin
]

# Initial resize for specific window instances.
WINDOW_SIZES = {
    "arch-assist": "30ppt 50ppt",
    "arch-assist-popup": "50ppt 40ppt",
}

# Guard to suppress cascading window::floating events from our own float commands.
_suppress = False


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
    if instance in WINDOW_SIZES:
        i3.command(f"[con_id={con.id}] resize set {WINDOW_SIZES[instance]}")
    _suppress = False

    update_gaps(i3)


def on_floating_change(i3, event):
    """Update gaps when a window is toggled between floating/tiling."""
    if not _suppress:
        update_gaps(i3, event)


i3 = i3ipc.Connection()

i3.on("window::new", on_new_window)
i3.on("window::close", update_gaps)
i3.on("window::move", update_gaps)
i3.on("window::floating", on_floating_change)
i3.on("window::focus", update_gaps)
i3.on("workspace::focus", update_gaps)

update_gaps(i3)
i3.main()
