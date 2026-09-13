# Carry animation tests

Run all 70 cases with Lua 5.5, from the dotfiles repository root:

```sh
bash .config/hypr/tests/run.sh
```

The six suites use a shared virtual compositor. They cover basic carry behavior,
input cadence and reversals, manual drag/resize handoff, workspace ownership and
stack order, rendered pin release, and adaptive timing and landing corrections.
They do not connect to Hyprland or move live windows.

`test_carry_render.lua` also models the workspace render offset independently of
the carry physics, including frame sampling and clock quantization. Its native
slide matches the `gentle` spring configured in `hyprland.lua` and Hyprland 0.56.2's
pinned/unpinned rendering behavior. Local window coordinates alone cannot detect
the snap caused by releasing a pin before the workspace slide settles.

Set `CARRY=/absolute/path/to/carry.lua` to exercise an alternative module. Run a
single suite with `lua5.5 .config/hypr/tests/test_carry_render.lua`, for example.
The core suite optionally writes trajectory CSVs to the current directory when
`DUMP=1`; leave it unset for an artifact-free run. Live visual testing is separate
and requires desktop-control approval.
