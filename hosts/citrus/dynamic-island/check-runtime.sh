#!/usr/bin/env bash
# Run in a Wayland session: nix shell nixpkgs#{quickshell,dbus,libnotify,python3} -c bash check-runtime.sh
set -euo pipefail
island_source=$(cd -- "$(dirname -- "$0")" && pwd)
if [[ ${1:-} != --inside ]]; then
    island_bus=$(mktemp /tmp/island-bus.XXXXXX)
    trap 'rm -f "$island_bus"' EXIT
    # No service directories: tests must not auto-start another set of desktop portals.
    cat > "$island_bus" <<'XML'
<busconfig>
  <type>session</type>
  <listen>unix:tmpdir=/tmp</listen>
  <auth>EXTERNAL</auth>
  <policy context="default">
    <allow send_destination="*"/>
    <allow receive_sender="*"/>
    <allow own="*"/>
  </policy>
</busconfig>
XML
    dbus-run-session --config-file="$island_bus" -- bash "$0" --inside
    exit
fi
island_temp=$(mktemp -d /tmp/island-check.XXXXXX)
cp "$island_source"/{shell.qml,Island.qml,Geometry.js,Desktop.qml,DesktopPages.qml} "$island_temp/"
export ISLAND_TEST=1 ISLAND_TEST_NOTIFICATIONS=1
export ISLAND_TEST_SETTINGS="$island_temp/settings.ini" QT_QPA_PLATFORM=wayland
cat > "$island_temp/actions" <<'PY'
#!/usr/bin/env python3
import json, sys
action = sys.argv[1]
result = {"ok": True, "action": action}
if action.startswith('brightness-'):
    result.update(available=True, percent=30 if action == 'brightness-up' else 25)
elif action.startswith('nightlight-'):
    result['enabled'] = False
elif action.startswith('power-'):
    result.update(profile='balanced', profiles=['power-saver', 'balanced'])
elif action == 'clipboard-list':
    result['items'] = [{'id': '1', 'text': 'Plain text clipboard preview'}]
elif action == 'windows-list':
    result['windows'] = [{'address': '0x123', 'title': 'Example window', 'app': 'example', 'workspace': '1'}]
elif action == 'wallpaper-list':
    result['wallpapers'] = []
print(json.dumps(result))
PY
chmod +x "$island_temp/actions"
export ISLAND_TEST_ACTION="$island_temp/actions"
qs -p "$island_temp" --no-color > "$island_temp/runtime.log" 2>&1 &
island_pid=$!
trap 'qs -p "$island_temp" kill >/dev/null 2>&1 || true; kill "$island_pid" 2>/dev/null || true; wait "$island_pid" 2>/dev/null || true' EXIT
island_ipc() { qs -p "$island_temp" ipc call island "$@"; }
for ((attempt=0; attempt<50; attempt++)); do
    if island_ipc status > "$island_temp/status.json" 2>/dev/null && [[ -s "$island_temp/status.json" ]]; then break; fi
    sleep 0.1
done
python3 - "$island_temp/status.json" <<'PY'
import json, sys
state = json.load(open(sys.argv[1]))
assert state['page'] == '' and not state['pinned'], state
PY
for page in launcher calendar controls notifications settings session wallpaper clipboard windows; do
    island_ipc "$page"
    sleep 0.5
    if [[ -n ${ISLAND_CAPTURE_SCREEN:-} ]]; then
        qs -p "$island_temp" ipc call "island-view-$ISLAND_CAPTURE_SCREEN" capture "$island_temp/$page.png"
    fi
    island_ipc status > "$island_temp/status.json"
    python3 - "$island_temp/status.json" "$page" <<'PY'
import json, sys
state = json.load(open(sys.argv[1]))
assert state['page'] == sys.argv[2] and state['pinned'], state
PY
done
island_ipc brightnessUp
sleep 0.4
island_ipc status > "$island_temp/status.json"
python3 - "$island_temp/status.json" <<'PY'
import json, sys
state = json.load(open(sys.argv[1]))
assert state['brightnessAvailable'] and state['brightness'] == 30, state
assert state['clipboardCount'] == 1 and state['windowCount'] == 1, state
assert not state['desktopBusy'] and not state['desktopError'], state
PY
island_ipc close
notify-send --app-name='Island check' --expire-time=1000 'Notification test' 'Plain text <b>stays plain</b>'
sleep 0.2
island_ipc status > "$island_temp/status.json"
python3 - "$island_temp/status.json" <<'PY'
import json, sys
state = json.load(open(sys.argv[1]))
assert state['notice'] == 'Notification test' and state['notifications'] == 1, state
PY
sleep 1.2
island_ipc status > "$island_temp/status.json"
python3 - "$island_temp/status.json" <<'PY'
import json, sys
assert json.load(open(sys.argv[1]))['notice'] == ''
PY
notify-send --urgency=critical --expire-time=1 'Persistent test' 'Critical notifications require dismissal.'
sleep 1.2
island_ipc status > "$island_temp/status.json"
python3 - "$island_temp/status.json" <<'PY'
import json, sys
assert json.load(open(sys.argv[1]))['notice'] == 'Persistent test'
PY
island_ipc close
island_ipc notch
sleep 0.6
island_ipc status > "$island_temp/status.json"
python3 - "$island_temp/status.json" <<'PY'
import json, sys
state = json.load(open(sys.argv[1]))
assert state['notch'] and not state['notice'], state
PY
# Exercise repeat transitions beyond the initial frame and QML collection cycle.
for ((cycle=0; cycle<8; cycle++)); do
    island_ipc toggle
    sleep 0.45
    island_ipc close
    sleep 0.45
done
island_ipc status > "$island_temp/status.json"
if rg 'ERROR|TypeError|ReferenceError|Binding loop|Cannot assign|Unable to assign' "$island_temp/runtime.log"; then
    exit 1
fi
echo "Island runtime checks passed; log: $island_temp/runtime.log"
