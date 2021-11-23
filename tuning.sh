#!/bin/bash

# typematic rate [time: 200ms, repeat rate: 40p/s]
xset r rate 200 40

# wireless mode // configuration for razer mamba mouse while wireless (undocked)
xinput set-prop "pointer:Razer Razer Mamba Dock" "libinput Accel Speed" -1

# wired mode // configuration for razer mamba mouse while wired (docked)
xinput set-prop "pointer:Razer Razer Mamba" "libinput Accel Speed" -1
