#!/usr/bin/env python3
"""
Dynamic left/right gaps for ultrawide monitors.
Adjusts left/right outer gaps based on tiled window count on the focused workspace.
"""

import i3ipc

# Left/right gap (pixels each side) by tiled window count.
GAP_SCHEDULE = [
    (1, 680),  # 1-2 windows: ~20% margin
    (3, 340),  # 3-4 windows: ~10% margin
    (5, 154),  # 5+ windows:  ~3% margin
]


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
    count = len(tiled)
    gap = get_gap(count)

    i3.command(f"gaps left current set {gap}; gaps right current set {gap}")


i3 = i3ipc.Connection()

i3.on("window::new", update_gaps)
i3.on("window::close", update_gaps)
i3.on("window::move", update_gaps)
i3.on("window::floating", update_gaps)
i3.on("window::focus", update_gaps)
i3.on("workspace::focus", update_gaps)

update_gaps(i3)
i3.main()
