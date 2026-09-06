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
cp "$island_source"/*.qml "$island_source/Geometry.js" "$island_temp/"
export ISLAND_TEST=1 ISLAND_TEST_NOTIFICATIONS=1
export ISLAND_TEST_SETTINGS="$island_temp/settings.ini" QT_QPA_PLATFORM=wayland
python3 - "$island_temp/shell.qml" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
source = path.read_text()
source = source.replace('function brightnessUp(): void {', '''function testBrightnessInputs(inputs: string): void {
            for (const args of JSON.parse(decodeURIComponent(inputs)))
                desktop.run(args);
        }
        function testMediaSelection(players: string): string {
            return root.selectPlayer(JSON.parse(decodeURIComponent(players)))?.identity || "";
        }
        function testPlayer(players: string): void {
            root.player = root.selectPlayer(JSON.parse(decodeURIComponent(players)));
            root.osd = "";
        }
        function brightnessUp(): void {''')
path.write_text(source)
path = path.with_name('Island.qml')
source = path.read_text().replace('function geometry(): string {', '''function testHover(entered: bool): void {
            window.updateHover(entered);
        }
        function testPopup(open: bool): void {
            window.openMenus = open ? 1 : 0;
        }
        function testLayout(): string {
            return JSON.stringify({
                width: surface.width, height: surface.height,
                contentLeft: expandedContent.x, contentTop: expandedContent.y,
                contentRight: surface.width - expandedContent.x - expandedContent.width,
                contentBottom: surface.height - expandedContent.y - expandedContent.height,
                listBottom: appList.mapToItem(surface, 0, appList.height).y,
                artworkCenter: artwork.mapToItem(surface, 0, artwork.height / 2).y,
                mediaTop: mediaDetails.mapToItem(surface, 0, 0).y,
                mediaBottom: mediaDetails.mapToItem(surface, 0, mediaDetails.height).y
            });
        }
        function geometry(): string {''')
path.write_text(source)
for number, color in enumerate(['#7aa2f7', '#9ece6a', '#bb9af7']):
    path.with_name(f'wallpaper-{number}.svg').write_text(
        f'<svg xmlns="http://www.w3.org/2000/svg" width="480" height="240">'
        f'<rect width="480" height="240" fill="{color}"/>'
        '<path d="M0 240L140 60L260 180L360 100L480 240Z" fill="#1a1b26"/></svg>')
PY
cat > "$island_temp/actions" <<'PY'
#!/usr/bin/env python3
import json, sys, time
from pathlib import Path
action = sys.argv[1]
result = {"ok": True, "action": action}
if action.startswith('brightness-'):
    directory = Path(__file__).parent
    state = directory / 'brightness'
    value = float(state.read_text()) if state.exists() else 25
    with (directory / 'brightness-calls').open('a') as log:
        log.write(action + '\n')
    time.sleep(0.2)  # Deliberately slower than a keyboard repeat.
    if (directory / 'fail-brightness').exists():
        result.update(ok=False, error={'message': 'Display disconnected'})
    else:
        if action == 'brightness-up': value = min(100, value + 5)
        elif action == 'brightness-down': value = max(0, value - 5)
        elif action == 'brightness-set': value = float(sys.argv[2])
        state.write_text(str(value))
        result.update(available=True, percent=value, backend='ddc', bus=3)
elif action.startswith('nightlight-'):
    result['enabled'] = False
elif action.startswith('power-'):
    result.update(profile='balanced', profiles=['power-saver', 'balanced'])
elif action == 'clipboard-list':
    result['items'] = [{'id': '1', 'text': 'Plain text clipboard preview'}]
elif action == 'windows-list':
    result['windows'] = [{'address': '0x123', 'title': 'Example window', 'app': 'example', 'workspace': '1'}]
elif action == 'wallpaper-list':
    result['wallpapers'] = [{'path': str(Path(__file__).with_name(f'wallpaper-{i}.svg')),
                             'name': name} for i, name in enumerate(['Blue hour', 'Quiet morning', 'Evening mountains'])]
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
island_view=$(qs -p "$island_temp" ipc show | rg '^target island-view-' | head -1 | cut -d' ' -f2)
python3 - "$island_temp/status.json" <<'PY'
import json, os, sys
state = json.load(open(sys.argv[1]))
assert state['page'] == '' and not state['pinned'], state
if os.environ.get('ISLAND_THEME'):
    theme = json.loads(os.environ['ISLAND_THEME'])
    assert state['theme']['background'] == '#000000', state
    for key in ['accent', 'fontFamily', 'fontSize']:
        assert state['theme'][key] == theme[key], state
PY
for page in launcher calendar controls notifications settings session wallpaper clipboard windows; do
    island_ipc "$page"
    sleep 0.5
    if [[ -n ${ISLAND_CAPTURE_SCREEN:-} ]]; then
        qs -p "$island_temp" ipc call "island-view-$ISLAND_CAPTURE_SCREEN" capture "$island_temp/$page.png"
    fi
    island_ipc status > "$island_temp/status.json"
    qs -p "$island_temp" ipc call "$island_view" testLayout > "$island_temp/layout.json"
    python3 - "$island_temp/status.json" "$page" "$island_temp/layout.json" <<'PY'
import json, sys
state = json.load(open(sys.argv[1]))
assert state['page'] == sys.argv[2] and state['pinned'], state
layout = json.load(open(sys.argv[3]))
for edge in ['contentLeft', 'contentTop', 'contentRight', 'contentBottom']:
    assert layout[edge] == 20, layout
if sys.argv[2] == 'launcher':
    assert abs(layout['listBottom'] - (layout['height'] - 20)) <= 1, layout
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
python3 - "$island_temp" <<'PY'
import json, subprocess, sys, time
from pathlib import Path
from urllib.parse import quote
directory = Path(sys.argv[1])
def ipc(*args):
    return subprocess.check_output(['qs', '-p', str(directory), 'ipc', 'call', 'island', *args], text=True)
def burst(inputs, expected, failure=False):
    log = directory / 'brightness-calls'
    before = len(log.read_text().splitlines())
    assert not ipc('testBrightnessInputs', quote(json.dumps(inputs), safe='')).strip()
    deadline = time.monotonic() + 3
    while True:
        state = json.loads(ipc('status'))
        if not state['desktopBusy']: break
        assert time.monotonic() < deadline, 'Brightness repeats kept a slow backlog'
        time.sleep(0.05)
    assert len(log.read_text().splitlines()) - before <= 2, 'Repeated unnecessary hardware calls'
    assert bool(state['desktopError']) == failure, state
    if not failure:
        assert state['brightness'] == expected, state
        assert float((directory / 'brightness').read_text()) == expected
burst([['brightness-up']] * 20 + [['brightness-down']] * 2, 90)
burst([['brightness-down']] * 25 + [['brightness-up']] * 2, 10)
burst([['brightness-set', 95], ['brightness-up'], ['brightness-up'],
       ['brightness-down'], ['windows-list'], ['brightness-set', 40],
       ['brightness-up'], ['brightness-down']], 40)
(directory / 'fail-brightness').touch()
burst([['brightness-up']] * 20, None, failure=True)
(directory / 'fail-brightness').unlink()
burst([['brightness-up']], 45)
idle = {'identity': 'Codex', 'isPlaying': False, 'playbackState': 0,
        'trackTitle': '', 'trackArtUrl': 'file:///app-icon.png'}
paused = {'identity': 'Music', 'isPlaying': False, 'playbackState': 2, 'trackTitle': 'Song'}
playing = {'identity': 'Radio', 'isPlaying': True, 'playbackState': 1, 'trackTitle': ''}
for players, expected in [([], ''), ([idle], ''), ([idle, paused], 'Music'),
                          ([idle, paused, playing], 'Radio'),
                          ([dict(idle, trackTitle='Old track')], '')]:
    assert ipc('testMediaSelection', quote(json.dumps(players), safe='')).strip() == expected
PY
python3 - "$island_temp" <<'PY'
import json, os, subprocess, sys, time
from pathlib import Path
from urllib.parse import quote
directory = Path(sys.argv[1])
def ipc(target, method, *args):
    return subprocess.check_output(['qs', '-p', str(directory), 'ipc', 'call', target, method, *args], text=True)
targets = subprocess.check_output(['qs', '-p', str(directory), 'ipc', 'show'], text=True)
view = next(line.split()[1] for line in targets.splitlines() if line.startswith('target island-view-'))
def geometry(): return json.loads(ipc(view, 'geometry'))
ipc('island', 'close')
ipc('island', 'testPlayer', quote('[]', safe=''))
ipc(view, 'testHover', 'true')
time.sleep(.5)
assert geometry()['expanded'], geometry()
if os.environ.get('ISLAND_CAPTURE_SCREEN'):
    ipc(view, 'capture', str(directory / 'media-empty.png'))
layout = json.loads(ipc(view, 'testLayout'))
assert abs(layout['artworkCenter'] - layout['height'] / 2) <= 1, layout
playing = {'identity': 'Music', 'isPlaying': True, 'playbackState': 1,
           'trackTitle': 'An evening on the coast — music for the long journey home', 'trackAlbum': 'Quiet places',
           'trackArtist': 'Example artist', 'canTogglePlaying': True,
           'canGoNext': True, 'canGoPrevious': True}
ipc('island', 'testPlayer', quote(json.dumps([playing]), safe=''))
time.sleep(.5)
layout = json.loads(ipc(view, 'testLayout'))
assert layout['mediaTop'] >= 19.5 and layout['mediaBottom'] <= layout['height'] - 19.5, layout
if os.environ.get('ISLAND_CAPTURE_SCREEN'):
    ipc(view, 'capture', str(directory / 'media-playing.png'))
ipc('island', 'testPlayer', quote('[]', safe=''))
ipc('island', 'brightnessUp')
time.sleep(.7)
assert geometry()['state'] == 'osd' and geometry()['height'] == 38, geometry()
if os.environ.get('ISLAND_CAPTURE_SCREEN'):
    ipc(view, 'capture', str(directory / 'osd.png'))
ipc('island', 'testPlayer', quote('[]', safe=''))
ipc('island', 'controls')
ipc(view, 'testHover', 'false')
time.sleep(.05)
ipc(view, 'testHover', 'true')
time.sleep(.25)
assert geometry()['expanded'], 'Brief gaps between controls must not collapse the panel'
ipc(view, 'testPopup', 'true')
ipc(view, 'testHover', 'false')
time.sleep(.25)
assert geometry()['expanded'] and geometry()['popupOpen'], geometry()
ipc(view, 'testPopup', 'false')
time.sleep(.7)
assert geometry()['height'] == 38 and not geometry()['expanded'], geometry()
assert json.loads(ipc('island', 'status'))['page'] == ''
if os.environ.get('ISLAND_CAPTURE_SCREEN'):
    ipc(view, 'capture', str(directory / 'collapsed.png'))
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
if [[ -n ${ISLAND_CAPTURE_SCREEN:-} ]]; then
    qs -p "$island_temp" ipc call "island-view-$ISLAND_CAPTURE_SCREEN" capture "$island_temp/notice.png"
fi
# Hover dismissal folds critical notifications without acknowledging them.
qs -p "$island_temp" ipc call "$island_view" testHover true
qs -p "$island_temp" ipc call "$island_view" testHover false
sleep 0.7
qs -p "$island_temp" ipc call "$island_view" geometry > "$island_temp/geometry.json"
island_ipc status > "$island_temp/status.json"
python3 - "$island_temp/geometry.json" "$island_temp/status.json" <<'PY'
import json, sys
assert json.load(open(sys.argv[1]))['height'] == 38
assert json.load(open(sys.argv[2]))['notice'] == 'Persistent test'
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
