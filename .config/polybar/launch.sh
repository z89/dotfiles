#!/usr/bin/env sh
 
killall -q polybar

polybar --reload primary &
