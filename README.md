# Raspberry Pi Home Assistant Kiosk

Turn a Raspberry Pi with a touchscreen into a dedicated fullscreen Home Assistant
display. The Pi boots directly into the HA dashboard — no desktop, no browser UI,
just Home Assistant. Controlled entirely by touch, with an on-screen keyboard for
text input.

## Features

- **Fullscreen kiosk** — Firefox opens automatically on boot, no address bar, no tab bar, no title bar
- **On-screen keyboard** — squeekboard appears automatically when tapping input fields
- **Display rotation** — configurable for portrait or landscape mounting
- **Touch calibration** — touch coordinates match the display orientation
- **Dark mode** — Home Assistant and all web content rendered in dark mode
- **Display power control** — display turns on/off based on presence detection via Home Assistant automations and MQTT
- **Fan control** — GPIO-connected fan activates automatically above a configurable temperature threshold
- **Fully automated setup** — single Ansible playbook configures everything from scratch

## Requirements

- Raspberry Pi running **Raspberry Pi OS Bookworm** (64-bit)
- Touchscreen (tested with Raspberry Pi Touch Display 2)
- Home Assistant running on the local network
- Home Assistant Mosquitto MQTT broker add-on (for display power control)
- GPIO fan with heatsink (optional, recommended for enclosed cases)
- Ansible on your local machine

---

## Quick Start

```bash
# 1. Edit hosts file with your Pi's IP and username
# 2. Adjust group_vars/all.yml (URL, display rotation, keyboard layout)
# 3. Run:
ansible-playbook kiosk.yml -i hosts --ask-become-pass

# 4. Reboot the Pi
ansible -i hosts kiosk -m reboot --ask-become-pass
```

After reboot, Firefox starts automatically in fullscreen showing Home Assistant.

---

## Background & Pitfalls

## What This Is About

The goal is to turn a Raspberry Pi running **Raspberry Pi OS Bookworm** into a
dedicated fullscreen kiosk display for **Home Assistant**, controlled via a
**touchscreen** (no keyboard, no mouse). The Pi boots directly into a browser
showing the HA dashboard. The user must be able to log into Home Assistant using
an **on-screen keyboard (OSK)**.

This sounds simple, but the OSK integration between the Wayland compositor
(labwc), the browser, and squeekboard (the default OSK on RPi OS Bookworm) is
fragile and full of pitfalls. Most of the effort in this setup went into getting
the OSK to actually appear when tapping an input field in the browser.

---

## System Details

- **OS:** Raspberry Pi OS Bookworm (Debian 12, aarch64)
- **Compositor:** labwc (Wayland)
- **Display Manager:** LightDM
- **OSK:** squeekboard (pre-installed, uses `zwp_text_input_v3` Wayland protocol)
- **Touchscreen:** Goodix Capacitive TouchScreen (DSI)
- **Browser:** Firefox (not Chromium — see pitfalls below)
- **SSH access:** available, via WSL on Windows using sshpass

---

## The Core Problem: On-Screen Keyboard

This was the hardest part. Here is a summary of everything tried and why it
failed or worked:

### Why Chromium was dropped

Chromium was tried first. It started fine in kiosk mode (`--kiosk`), but
squeekboard never appeared when tapping input fields, even with:
- `--enable-features=WaylandTextInputV3`
- `--ozone-platform=wayland`

The root cause: Chromium's implementation of `zwp_text_input_v3` (the Wayland
protocol that triggers squeekboard) does not work reliably with squeekboard on
this setup. Firefox has much better support for this protocol.

### Why `--kiosk` cannot be used (in any browser)

Both `--kiosk` in Firefox and the labwc `ToggleFullscreen` window rule cause the
browser to enter **true compositor fullscreen**. In this state, the browser grabs
input focus exclusively and squeekboard is never triggered. The OSK simply does
not appear.

**Do not use `--kiosk` or `ToggleFullscreen` if you need the OSK.**

### The working solution

Use `Maximize` (not fullscreen) as the labwc window rule, combined with
`serverDecoration=no` to hide the title bar. The window fills the entire screen
and looks like fullscreen, but does not block the OSK.

Firefox must be started with:
- `MOZ_ENABLE_WAYLAND=1` — ensures native Wayland mode, not XWayland
- `XDG_SESSION_TYPE=wayland` — must be set if starting Firefox from SSH/scripts

If Firefox is started from the labwc autostart file (`~/.config/labwc/autostart`),
the correct environment is inherited automatically after a proper boot.
If started manually via SSH, these variables must be set explicitly.

### squeekboard debug tip

To test whether squeekboard is working at all (independent of the browser),
trigger it manually via D-Bus:

```bash
DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
  dbus-send --session --dest=sm.puri.OSK0 /sm/puri/OSK0 \
  sm.puri.OSK0.SetVisible boolean:true
```

If the keyboard appears, squeekboard is fine and the problem is in the
browser's text-input protocol handling. If it does not appear, there is a
deeper issue with squeekboard or the Wayland session environment.

---

## Step-by-Step Setup

### Step 1: Configure Auto-Login

File: `/etc/lightdm/lightdm.conf`

In the `[Seat:*]` section:

```ini
autologin-user=USERNAME
autologin-session=LXDE-pi-labwc
```

---

### Step 2: Set Wayland Environment Variables

File: `~/.config/labwc/environment`

```
XKB_DEFAULT_MODEL=pc105
XKB_DEFAULT_LAYOUT=de
MOZ_ENABLE_WAYLAND=1
```

This file is sourced by labwc at session start. `MOZ_ENABLE_WAYLAND=1` ensures
Firefox uses native Wayland when launched from the autostart.

---

### Step 3: Disable the Top Panel

`wf-panel-pi` is launched from the system-wide labwc autostart. Remove it:

```bash
sudo sed -i '/wf-panel-pi/d' /etc/xdg/labwc/autostart
```

The user autostart (`~/.config/labwc/autostart`) does NOT override the system
one — both are executed. So the system file must be edited directly.

---

### Step 4: labwc Window Rule for Firefox

File: `~/.config/labwc/rc.xml`

Add before `</openbox_config>`:

```xml
<windowRules>
  <windowRule identifier="firefox*" serverDecoration="no">
    <action name="Maximize"/>
  </windowRule>
</windowRules>
```

**Important notes on labwc syntax:**
- The action name is `Maximize`, not `Fullscreen` or `ToggleFullscreen`
- `identifier` uses glob patterns (e.g. `firefox*`), not regex or `matchType`
- `serverDecoration="no"` removes the title bar
- Changes to rc.xml require a labwc reload (`kill -HUP $(pidof labwc)`) or reboot to take effect

---

### Step 5: Firefox Autostart

File: `~/.config/labwc/autostart`

```bash
swayidle -w timeout 600 "wlopm --off \*" resume "wlopm --on \*" &
unclutter --timeout 1 &
sleep 5 && firefox http://homeassistant.local:8123 &
```

- `sleep 5`: gives the network time to resolve `homeassistant.local` via mDNS.
  Without this, Firefox may start before the hostname is resolvable and show a
  blank page.
- `unclutter`: hides the mouse cursor after 1 second (install with `sudo apt install unclutter`)

---

### Step 6: Hide Firefox Address Bar and Tab Bar

Firefox must be **fully closed** before editing `prefs.js`. Firefox overwrites
this file on exit, discarding any changes made while it was running.

#### 6a: Enable userChrome.css support

```bash
# Find profile directory
ls ~/.mozilla/firefox/

# Append pref (replace PROFILENAME with the actual folder name, e.g. p0oje7ca.default-release)
echo 'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);' \
  >> ~/.mozilla/firefox/PROFILENAME/prefs.js
```

#### 6b: Create userChrome.css

```bash
mkdir -p ~/.mozilla/firefox/PROFILENAME/chrome
cat > ~/.mozilla/firefox/PROFILENAME/chrome/userChrome.css << 'EOF'
#nav-bar { visibility: collapse !important; }
#TabsToolbar { visibility: collapse !important; }
EOF
```

**Critical:** Use `visibility: collapse`, NOT `display: none`.

`display: none` on `#nav-bar` or `#navigator-toolbox` causes a completely white
screen in Firefox on Wayland (confirmed on Firefox 142). The content area fails
to render. `visibility: collapse` hides the elements while preserving the layout
and renders the page correctly.

---

### Step 7: Display Control via MQTT and Home Assistant

The display can be turned on/off by Home Assistant based on presence detection.
When a presence sensor detects someone, HA publishes an MQTT message to the Pi,
which immediately turns the display on or off.

#### 7a: Create MQTT user in HA

In HA → **Settings → Apps → Mosquitto broker → Configuration → Logins → Add**:
- Username: `mqtt-kiosk` (or any name)
- Password: choose a strong password

Store the password in `group_vars/secrets.yml` (gitignored):
```yaml
mqtt_password: YOUR_PASSWORD
```

#### 7b: Configure MQTT variables

In `group_vars/all.yml`:
```yaml
mqtt_host: homeassistant.local
mqtt_port: 1883
mqtt_user: mqtt-kiosk
mqtt_topic: kiosk/display
```

The Ansible playbook deploys `/usr/local/bin/kiosk-display.sh` which subscribes
to `kiosk/display` and calls `wlopm --on/--off` accordingly. It is started
automatically via the labwc autostart.

#### 7c: Create HA automations

In HA → **Settings → Automations → Create automation → three dots → Edit as YAML**:

**Display on when presence detected:**
```yaml
alias: Kiosk Display - Presence detected
trigger:
  - platform: state
    entity_id: binary_sensor.YOUR_PRESENCE_SENSOR
    to: "on"
action:
  - service: mqtt.publish
    data:
      topic: kiosk/display
      payload: "on"
mode: single
```

**Display off when no presence:**
```yaml
alias: Kiosk Display - No presence
trigger:
  - platform: state
    entity_id: binary_sensor.YOUR_PRESENCE_SENSOR
    to: "off"
action:
  - service: mqtt.publish
    data:
      topic: kiosk/display
      payload: "off"
mode: single
```

> The Pi's `kiosk-display.sh` script subscribes to the MQTT topic and reacts
> instantly — no polling, no delay.

---

### Step 8: Rotate Display and Touch Input (optional)

If the display is mounted in landscape orientation but the panel is physically
vertical (portrait), both the display output and the touch coordinates need to
be rotated.

#### 7a: Rotate the display via kanshi

File: `~/.config/kanshi/config`

Find the output name first:
```bash
WAYLAND_DISPLAY=wayland-0 XDG_RUNTIME_DIR=/run/user/1000 wlr-randr
```

Then set the rotation (replace `DSI-1` and mode if different):

```
profile {
    output DSI-1 enable mode 720x1280@60.038 position 0,0 transform 90
}
```

Transform values:
- `normal` — no rotation
- `90` — 90° clockwise
- `180` — 180°
- `270` — 90° counter-clockwise

Reload kanshi without rebooting:
```bash
killall -HUP kanshi
```

#### 7b: Rotate touch input to match

The display rotation does not automatically rotate touch coordinates on this
setup. A udev calibration matrix is needed. Create the rule file:

```bash
sudo nano /etc/udev/rules.d/99-touchscreen-rotate.rules
```

Content for **90° clockwise** (transform 90):
```
ACTION=="add|change", ATTRS{name}=="Goodix Capacitive TouchScreen", ENV{LIBINPUT_CALIBRATION_MATRIX}="0 -1 1 1 0 0"
```

Other orientations:

| Display transform | Calibration matrix |
|---|---|
| `90` (CW) | `0 -1 1 1 0 0` |
| `270` (CCW) | `0 1 0 -1 0 1` |
| `180` | `-1 0 1 0 -1 1` |

Find the device name to use in `ATTRS{name}`:
```bash
cat /proc/bus/input/devices | grep -A2 -i touch
```

Apply the rule — requires a **reboot** to take effect:
```bash
sudo udevadm control --reload-rules
sudo reboot
```

> **Note:** The udev calibration matrix is applied by libinput before the
> compositor sees the events. Do not combine it with a compositor-level
> touch transform — that would apply the rotation twice.

---

### Step 9: Enable Dark Mode

The cleanest approach is to configure Firefox to report `prefers-color-scheme: dark`
to all web content. Home Assistant (and any other website) will automatically
switch to dark mode — no changes to HA configuration required.

Firefox must be **closed** before editing `prefs.js`.

```bash
python3 -c "
profile = '/home/USERNAME/.mozilla/firefox/PROFILENAME/prefs.js'
content = open(profile).read()
if 'prefers-color-scheme.content-override' not in content:
    content += 'user_pref(\"layout.css.prefers-color-scheme.content-override\", 0);\n'
open(profile, 'w').write(content)
"
```

The value `0` = dark, `1` = light, `2` = follow system default.

> **Do not use `echo` to append to prefs.js** — shell quoting will strip the
> double quotes from the pref name and value, producing a malformed entry that
> Firefox silently ignores. Always use Python or a text editor.

---

## Pitfalls Summary

| Pitfall | Details |
|---|---|
| Using `--kiosk` flag | Blocks OSK in both Firefox and Chromium — do not use |
| Using `ToggleFullscreen` in labwc | Same problem as `--kiosk` — OSK does not appear |
| Using Chromium | `zwp_text_input_v3` does not work reliably with squeekboard on RPi OS Bookworm |
| `display: none` in userChrome.css | Causes white/blank screen in Firefox on Wayland — use `visibility: collapse` |
| Editing prefs.js while Firefox runs | Firefox overwrites it on exit, changes are lost |
| Starting Firefox via SSH without env vars | Firefox falls back to XWayland (`XDG_SESSION_TYPE=tty`), OSK stops working — set `MOZ_ENABLE_WAYLAND=1` and `XDG_SESSION_TYPE=wayland` explicitly |
| `labwc --reconfigure` via SSH | Requires `LABWC_PID` env var, not set in SSH sessions — use `kill -HUP $(pidof labwc)` instead, or reboot |
| User autostart overrides system autostart | It does not — both `/etc/xdg/labwc/autostart` and `~/.config/labwc/autostart` are executed |
| Display rotated but touches are wrong | Kanshi/wlr output rotation does not automatically rotate touch coordinates — add a udev `LIBINPUT_CALIBRATION_MATRIX` rule and reboot |
| Touch calibration seems doubled | Do not combine a udev calibration matrix with a compositor touch transform — use one or the other |
| MQTT "not authorised" error | User added in HA People but not in Mosquitto config — add user explicitly in Settings → Apps → Mosquitto broker → Configuration → Logins |
| Dark mode pref not applied | Quotes were stripped when using `echo` to write prefs.js — always use Python to write Firefox preferences |
| Firefox window small after labwc reconfigure | labwc window rules may not re-apply to already-open windows — start Firefox with `--maximized` flag to ensure it always opens maximized |

---

## Verification

After a clean reboot the following should be true:

**Boot & display:**
1. Pi boots directly to Firefox — no login screen, no desktop, no panel
2. Firefox shows the HA dashboard in fullscreen after ~5 seconds
3. No address bar, no tab bar, no title bar visible
4. Home Assistant is displayed in dark mode

**Touch & keyboard:**
5. Tapping anywhere on the screen works correctly (coordinates match orientation)
6. Tapping an input field (e.g. HA login) opens squeekboard at the bottom of the screen

**MQTT display control:**
7. Test manually from the Pi or any machine with `mosquitto_pub`:
```bash
mosquitto_pub -h homeassistant.local -p 1883 -u mqtt-kiosk -P YOUR_PASSWORD -t kiosk/display -m off
mosquitto_pub -h homeassistant.local -p 1883 -u mqtt-kiosk -P YOUR_PASSWORD -t kiosk/display -m on
```
8. When the HA presence sensor changes to `off`, the display turns off
9. When the HA presence sensor changes to `on`, the display turns on

**MQTT subscriber check:**
```bash
ssh USER@PI_IP 'ps aux | grep kiosk-display | grep -v grep'
```
Should show the `kiosk-display.sh` process running.
