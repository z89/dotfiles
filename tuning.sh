#!/bin/bash

# typematic rate [time: 200ms, repeat rate: 40p/s]
xset r rate 200 40

# wirless mode speed // specific razer mouse configuration for razer mamba
xinput set-prop "pointer:Razer Razer Mamba Dock" "libinput Accel Speed" -1

# wired mode // specific razer mouse configuration for razer mamba
#xinput set-prop "pointer:Razer Razer Mamba" "libinput Accel Speed" -1
