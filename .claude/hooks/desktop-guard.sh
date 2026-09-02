#!/bin/bash
# Forces an explicit user approval prompt before any Bash command that can
# take over the desktop or mutate system state.  ARCH LINUX / systemd variant.
# Outputs PreToolUse JSON: permissionDecision "ask" => user must confirm.
#
# Covers X11 and Wayland input/capture tooling, systemd service + power control,
# pacman/AUR/flatpak/snap package operations, and destructive filesystem ops.

INPUT=$(cat)
CMD=$(jq -r '.tool_input.command // empty' <<<"$INPUT" 2>/dev/null)
[ -z "$CMD" ] && exit 0

REASON=""
add(){ REASON="${REASON:+$REASON; }$1"; }

G=/usr/bin/grep          # pin: never inherit an aliased/shadowed grep
B='(^|[[:space:];&|(`\\])' # word boundary incl. subshell, backtick, backslash-escape
# Command position: the word must START a command, not merely appear after a
# space. Required for tool names that are also ordinary words (import, mount,
# passwd) — with only B, `grep -rn import src/` matches its own search term.
# Absorbs, in order: any opener (including `{`, `(`, `&&`, `||`, `$(` via the
# class), VAR=val prefixes, and wrappers WITH their arguments, repeated — so
# `env FOO=1 mount`, `timeout 5 umount` and `xargs -I{} mount {}` are caught.
# It over-matches slightly (`time grep import x` prompts). That trade is
# deliberate: over-matching costs one prompt, under-matching means the guard
# silently is not there.
# ACCEPTED LIMIT: a command inside a quoted payload — `sg docker -c "mount …"`,
# `bash -c '…'` — cannot be seen by any command-position boundary. A hook sees
# the command string, not what a subshell will later parse out of a string.
C='(^|[;&|`{(])[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*((sudo|doas|pkexec|env|nohup|time|timeout|command|exec|setsid|stdbuf|nice|ionice|watch|xargs|sg|newgrp|if|then|else|elif|do|while|until)([[:space:]]+[^[:space:];&|]+)*[[:space:]]+)*'
m(){ $G -qE "$1" <<<"$CMD"; }

# --- Desktop takeover -------------------------------------------------------
m "${B}(xdg-open|gio[[:space:]]+open|gnome-open|kde-open5?)([[:space:]]|\$)"     && add "opens an app/window/settings pane"
m "${B}xdg-settings[[:space:]]+set"                                              && add "changes default applications"
m "${B}(xdotool|ydotool|wtype|dotool|xte)([[:space:]]|\$)"                        && add "synthesises input (keystroke/click/mouse)"
m "${B}(wmctrl|swaymsg|hyprctl|xprop[[:space:]]+-set|i3-msg|qdbus)([[:space:]]|\$)" && add "manipulates windows / drives the compositor"
m "${B}(grim|slurp|scrot|maim|spectacle|flameshot|gnome-screenshot)([[:space:]]|\$)" && add "captures the screen"
m "${C}import([[:space:]]|\$)"                                                  && add "captures the screen"
m "${B}xrandr([[:space:]]+[^[:space:]]+)*[[:space:]]+--(output|mode|off|rate|primary)" && add "changes display configuration"

# --- Persistent desktop state ----------------------------------------------
m "${B}gsettings[[:space:]]+(set|reset)"                                          && add "writes desktop preferences (gsettings)"
m "${B}dconf[[:space:]]+(write|reset|load)"                                       && add "writes desktop preferences (dconf)"
m "${B}kwriteconfig[0-9]*([[:space:]]|\$)"                                        && add "writes KDE configuration"
m "${B}xfconf-query([[:space:]]+[^[:space:]]+)*[[:space:]]+(-s|--set)"            && add "writes Xfce configuration"

# --- Process + service control ---------------------------------------------
m "${B}(pkill|killall)([[:space:]]|\$)"                                           && add "kills processes"
m "${B}kill[[:space:]]+-(9|SIGKILL)"                                              && add "force-kills a process"
m "${C}kill([[:space:]]|\$)"                                                     && add "kills processes"
m "${B}systemctl([[:space:]]+--[^[:space:]]+)*[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|isolate|edit|set-property|kill)" && add "changes systemd services"
m "${B}(systemd-run|loginctl[[:space:]]+(terminate|kill|lock|unlock|activate))"   && add "controls sessions/transient units"
m "${B}(shutdown|reboot|poweroff|halt)([[:space:]]|\$)"                           && add "powers off or reboots the machine"
m "${B}systemctl[[:space:]]+(poweroff|reboot|suspend|hibernate|hybrid-sleep)"     && add "powers off / suspends the machine"

# --- Software installation --------------------------------------------------
m "${B}(sudo|doas|pkexec)([[:space:]]|\$)"                                        && add "runs with root privileges"
# -Si/-Ss/-Sl/-Sp are queries, not writes; -S/-Sy/-Su/-R*/-U are. Long forms too.
{ m "${B}pacman([[:space:]]+[^[:space:]]+)*[[:space:]]+-[A-Za-z]*S([^islp]|\$)" \
  || m "${B}pacman([[:space:]]+[^[:space:]]+)*[[:space:]]+-[A-Za-z]*[RU]" \
  || m "${B}pacman([[:space:]]+[^[:space:]]+)*[[:space:]]+--(sync|remove|upgrade)([^a-zA-Z]|\$)"; } \
                                                                                  && add "installs/removes packages (pacman)"
m "${B}(yay|paru|pamac|trizen|pikaur)([[:space:]]|\$)"                            && add "installs/removes packages (AUR helper)"
m "${B}makepkg([[:space:]]+[^[:space:]]+)*[[:space:]]+(-[a-zA-Z]*i|--install)"    && add "builds and installs a package"
m "${B}(flatpak|snap)[[:space:]]+(install|uninstall|remove|update)"               && add "installs/removes sandboxed apps"

# --- Persistent system configuration ---------------------------------------
m "${B}(timedatectl|hostnamectl|localectl)[[:space:]]+set-"                       && add "changes system configuration"
m "${B}(mkinitcpio|grub-mkconfig|grub-install|bootctl|efibootmgr)([[:space:]]|\$)" && add "modifies boot configuration"
m "${B}nmcli[[:space:]]+(c|con|connection|d|dev|device|r|radio)[[:space:]]+(add|mod|modify|delete|del|up|down|off|on)" && add "changes network configuration"
m "${B}(ufw|iptables|ip6tables|nft|firewall-cmd)([[:space:]]|\$)"                 && add "changes firewall rules"
m "${B}(useradd|usermod|userdel|groupadd|groupmod|groupdel|chsh|visudo)([[:space:]]|\$)" && add "changes users/groups/credentials"
m "${C}passwd([[:space:]]|\$)"                                                   && add "changes users/groups/credentials"
m "${C}(mount|umount|swapon|swapoff)([[:space:]]|\$)"                             && add "changes mounted filesystems"

# --- Destructive filesystem -------------------------------------------------
m "${B}rm[[:space:]]+(-[a-zA-Z]*[rf]|--recursive|--force)"                        && add "recursively/forcibly deletes files"
m "${B}(shred|mkfs(\.[a-z0-9]+)?|fdisk|parted|sgdisk|wipefs)([[:space:]]|\$)"     && add "destroys filesystem/partition data"
m "${B}dd([[:space:]]+[^[:space:]]+)*[[:space:]]+of="                             && add "writes a raw device/file image"
m "${B}(chown|chmod)[[:space:]]+(-[a-zA-Z]*R|--recursive)"                        && add "recursively changes ownership/permissions"

[ -z "$REASON" ] && exit 0

jq -cn --arg r "$REASON" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "ask",
    permissionDecisionReason: ("BLOCKED BY DESKTOP GUARD — this command " + $r + ". Per ~/.claude/CLAUDE.md Hard Rule #1, Claude must post a full permission request (exact commands, expected result, duration, risk, undo plan, abort plan) and receive an explicit yes BEFORE running this. Approve here only if that request was made and you agreed to it.")
  }
}'
