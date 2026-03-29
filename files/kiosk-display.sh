#!/bin/bash
# Kiosk display control via MQTT + touch wake
# Subscribes to {{ mqtt_topic }} and controls display power with fade effect

export WAYLAND_DISPLAY=wayland-0
export XDG_RUNTIME_DIR=/run/user/$(id -u)

BACKLIGHT=/sys/class/backlight/10-0045/brightness
MAX_BRIGHTNESS=31
FADE_STEPS=30
FADE_DELAY=0.06  # seconds per step, ~1.8s total fade
FADE_PID=""
STATE_FILE=/tmp/kiosk-display-state
TOUCH_DEV=/dev/input/event4

echo "on" > "$STATE_FILE"

# Reset swayidle timer and restore Firefox focus
poke_idle() {
    ydotool mousemove --absolute -x 360 -y 640 2>/dev/null
    ydotool click 1 2>/dev/null
}

kill_fade() {
    if [ -n "$FADE_PID" ] && kill -0 "$FADE_PID" 2>/dev/null; then
        kill "$FADE_PID" 2>/dev/null
        wait "$FADE_PID" 2>/dev/null
    fi
}

fade_in() {
    wlopm --on {{ display_output }}
    echo 0 > "$BACKLIGHT"
    for i in $(seq 1 $FADE_STEPS); do
        echo $((MAX_BRIGHTNESS * i / FADE_STEPS)) > "$BACKLIGHT"
        sleep $FADE_DELAY
    done
    echo "on" > "$STATE_FILE"
    poke_idle
}

fade_out() {
    for i in $(seq $((FADE_STEPS - 1)) -1 0); do
        echo $((MAX_BRIGHTNESS * i / FADE_STEPS)) > "$BACKLIGHT"
        sleep $FADE_DELAY
    done
    wlopm --off {{ display_output }}
    echo "off" > "$STATE_FILE"
}

# Touch wake: block-read touch input, wake if display is off
(
    exec 3< "$TOUCH_DEV"
    while true; do
        # Block until a touch event occurs
        dd bs=24 count=1 <&3 > /dev/null 2>&1
        if [ "$(cat $STATE_FILE)" = "off" ]; then
            echo "on" > "$STATE_FILE"
            fade_in
        fi
    done
) &

mosquitto_sub \
  -h {{ mqtt_host }} \
  -p {{ mqtt_port }} \
  -u {{ mqtt_user }} \
  -P {{ mqtt_password }} \
  -t {{ mqtt_topic }} \
  --will-topic {{ mqtt_topic }}/status \
  --will-payload offline \
  -R | while read -r msg; do
    case "$msg" in
      on)
        if [ "$(cat $STATE_FILE)" = "off" ]; then
            kill_fade
            fade_in & FADE_PID=$!
        fi
        ;;
      off)
        if [ "$(cat $STATE_FILE)" = "on" ]; then
            kill_fade
            fade_out & FADE_PID=$!
        fi
        ;;
    esac
done
