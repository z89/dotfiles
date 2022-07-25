#!/bin/bash

# typematic rate [time: 200ms, repeat rate: 40p/s]
xset r rate 300 50

# wireless mode // configuration for razer mamba mouse while wireless (undocked)
xinput set-prop "pointer:Razer Razer Mamba Dock" "libinput Accel Speed" -0.8

# wired mode // configuration for razer mamba mouse while wired (docked)
xinput set-prop "pointer:Razer Razer Mamba" "libinput Accel Speed" -0.8
