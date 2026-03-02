#!/usr/bin/env sh

# terminate already running bar instances
killall -q polybar

# wait until the processes have been shut down
while pgrep -u $UID -x polybar >/dev/null; do
  kill -9 $(pgrep -u $UID -x polybar) 2>/dev/null
  sleep 0.3
done

# launch bars
polybar --reload primary &
polybar --reload secondary &
