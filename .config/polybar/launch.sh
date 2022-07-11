#!/usr/bin/env sh
 
# Terminate already running bar instances
killall -q polybar
 
# Wait until the processes have been shut down
while pgrep -x polybar >/dev/null; do sleep 1; done
 
polybar --reload primary &
polybar --reload secondary &

#symlink spotify config
#ln -sf /tmp/polybar_mqueue.$! /tmp/ipc-bottom

#echo message >/tmp/ipc-bottom
