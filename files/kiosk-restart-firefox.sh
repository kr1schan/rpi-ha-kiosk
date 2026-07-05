#!/bin/bash
# Nightly Firefox restart for kiosk (invoked by cron)
# Restarts Firefox as user krischan with correct Wayland env.
#
# The Wayland output must be enabled while Firefox starts, otherwise labwc
# has no valid output geometry and cannot maximize the window (it ends up
# small in the top-left corner). We enable the output without touching the
# backlight, so if the screen was off it stays visually dark, then restore
# the previous power state after Firefox has mapped and maximized.

export WAYLAND_DISPLAY=wayland-0
export XDG_RUNTIME_DIR=/run/user/$(id -u)
export MOZ_ENABLE_WAYLAND=1

STATE_FILE=/tmp/kiosk-display-state
PREV_STATE=$(cat "$STATE_FILE" 2>/dev/null)

# Ensure the output is enabled so labwc can maximize Firefox correctly
wlopm --on {{ display_output }}

pkill -x firefox
sleep 5
nohup firefox --maximized {{ kiosk_url }} >/dev/null 2>&1 </dev/null &
disown

# Give Firefox time to map and get maximized by the labwc window rule
sleep 15

# Restore the previous power state: if the screen was off before the
# restart, turn the output back off (backlight was never raised)
if [ "$PREV_STATE" = "off" ]; then
    wlopm --off {{ display_output }}
fi
