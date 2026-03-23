#!/bin/bash
# Kiosk display control via MQTT
# Subscribes to {{ mqtt_topic }} and controls display power with fade effect

export WAYLAND_DISPLAY=wayland-0
export XDG_RUNTIME_DIR=/run/user/$(id -u)

BACKLIGHT=/sys/class/backlight/10-0045/brightness
MAX_BRIGHTNESS=31
FADE_STEPS=20
FADE_DELAY=0.04  # seconds per step → ~0.8s total fade

fade_in() {
    wlopm --on {{ display_output }}
    echo 0 > "$BACKLIGHT"  # prevent flash at full brightness on wakeup
    # Reload Firefox while screen is still dark to refresh clock etc.
    ydotool key 63:1 63:0  # F5
    sleep 1.5
    # Restore focus
    ydotool mousemove 360 640
    ydotool click 1
    sleep 0.2
    for i in $(seq 1 $FADE_STEPS); do
        echo $((MAX_BRIGHTNESS * i / FADE_STEPS)) > "$BACKLIGHT"
        sleep $FADE_DELAY
    done
}

fade_out() {
    for i in $(seq $((FADE_STEPS - 1)) -1 0); do
        echo $((MAX_BRIGHTNESS * i / FADE_STEPS)) > "$BACKLIGHT"
        sleep $FADE_DELAY
    done
    wlopm --off {{ display_output }}
}

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
      on)  fade_in ;;
      off) fade_out ;;
    esac
done
