#!/usr/bin/env sh
 
# Terminate already running bar instances
killall -q polybar
 
# Wait until the processes have been shut down
while pgrep -x polybar >/dev/null; do sleep 1; done
 
# Launch bar1 and bar2
if type "xrandr"; then
  for m in $(xrandr --query | grep " connected" | cut -d" " -f1); do
    MONITOR=$m polybar --reload z89 &
  done
else
  polybar --reload z89 &
fi

#symlink spotify config
ln -sf /tmp/polybar_mqueue.$! /tmp/ipc-bottom

echo message >/tmp/ipc-bottom
