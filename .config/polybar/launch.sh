#!/usr/bin/env sh
 
# Terminate already running bar instances
killall -q polybar
 
# Wait until the processes have been shut down
while pgrep -x polybar >/dev/null; do sleep 1; done
 
MONITOR=DVI-D-0 polybar --reload primary &
MONITOR=HDMI-0 polybar --reload secondary &

#symlink spotify config
#ln -sf /tmp/polybar_mqueue.$! /tmp/ipc-bottom

#echo message >/tmp/ipc-bottom
