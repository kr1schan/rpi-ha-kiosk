#!/bin/bash
# Nightly Firefox restart for kiosk (invoked by cron)
# Restarts Firefox as user krischan with correct Wayland env

export WAYLAND_DISPLAY=wayland-0
export XDG_RUNTIME_DIR=/run/user/$(id -u)
export MOZ_ENABLE_WAYLAND=1

pkill -x firefox
sleep 5
nohup firefox --maximized {{ kiosk_url }} >/dev/null 2>&1 </dev/null &
disown
