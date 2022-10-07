#!/usr/bin/env sh
 
# Terminate already running bar instances
killall -q redshift-gtk
 
# Wait until the processes have been shut down
while pgrep -x redshift-gtk >/dev/null; do sleep 1; done

redshift-gtk &
