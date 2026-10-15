export PATH="/home/archie/Downloads/flutter/bin:$PATH"
# No Quickshell reload popup (top-left); qs-reload-notify.service shows reloads as DMS notifications.
export QS_NO_RELOAD_POPUP=1
[ -r "$HOME/.zshenv.local" ] && . "$HOME/.zshenv.local"

# ssh asks for a key passphrase in a window when it has no terminal (agent sessions, editors)
export SSH_ASKPASS="$HOME/.local/bin/ssh-passphrase-askpass"
