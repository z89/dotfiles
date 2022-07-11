#!/usr/bin/env bash

theme="rofi"
dir="$HOME/.config/rofi/"

rofi -no-lazy-grab -show drun -modi drun -icon-theme "Papirus" -show-icons -theme $dir/"$theme"
