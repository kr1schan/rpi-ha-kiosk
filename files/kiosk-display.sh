#!/bin/bash
# Kiosk display control via MQTT
# Subscribes to {{ mqtt_topic }} and controls display power accordingly

export WAYLAND_DISPLAY=wayland-0
export XDG_RUNTIME_DIR=/run/user/$(id -u)

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
      on)  wlopm --on {{ display_output }} ;;
      off) wlopm --off {{ display_output }} ;;
    esac
done
