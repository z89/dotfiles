#!/usr/bin/env bash

theme="custom"
dir="$HOME/.config/wpg/templates"

rofi -no-lazy-grab -show drun -modi drun -theme $dir/"$theme"
