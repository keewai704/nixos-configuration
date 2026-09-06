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
            root.players = JSON.parse(decodeURIComponent(players)).map((p, i) => Object.assign(p, {dbusName: p.dbusName || "test-" + i, positionChanged: () => {}}));
            root.preferredPlayer = "";
            root.osd = "";
        }
        function testSeek(position: real): real {
            root.seekTo(position);
            return root.player?.position || 0;
        }
        function testDnd(enabled: bool): void { preferences.dnd = enabled; }
        function testHistory(): string { return JSON.stringify(Array.from({length: history.count}, (_, i) => history.get(i))); }
        function brightnessUp(): void {''')
path.write_text(source)
path = path.with_name('Island.qml')
source = path.read_text().replace('function geometry(): string {', '''function testHover(entered: bool): void {
            window.updateHover(entered);
        }
        function testPopup(open: bool): void {
            window.openMenus = open ? 1 : 0;
        }
        function testSelectPlayer(index: int): void { playerPicker.activated(index); }
        function testPlayerPopup(open: bool): void { if (open) playerPicker.popup.open(); else playerPicker.popup.close(); }
        function captureMenu(path: string): void { playerPicker.popup.contentItem.grabToImage(result => result.saveToFile(path)); }
        function testMicMuted(muted: bool): void { window.testMicMuted = muted; }
        function testLayout(): string {
            return JSON.stringify({
                width: surface.width, height: surface.height,
                contentLeft: expandedContent.x, contentTop: expandedContent.y,
                contentRight: surface.width - expandedContent.x - expandedContent.width,
                contentBottom: surface.height - expandedContent.y - expandedContent.height,
                listBottom: appList.mapToItem(surface, 0, appList.height).y,
                artworkCenter: artwork.mapToItem(surface, 0, artwork.height / 2).y,
                mediaTop: mediaDetails.mapToItem(surface, 0, 0).y,
                mediaBottom: mediaDetails.mapToItem(surface, 0, mediaDetails.height).y,
                mediaVisible: mediaContent.visible, seekVisible: seekBar.visible,
                seekEnabled: seekBar.enabled, positionTimer: positionTimer.running,
                artAvailable: artwork.available, artSource: artwork.source.toString(),
                art: artwork.testState(),
                compactNotice: compactNotice.visible, unread: shell.unreadCount,
                statusWidth: compactStatus.implicitWidth, micMuted: window.micMuted,
                clockRight: time.x + time.width, statusLeft: compactStatus.x,
                menu: {x: playerPicker.popup.x, y: playerPicker.popup.y, width: playerPicker.popup.width, height: playerPicker.popup.height}
            });
        }
        function geometry(): string {''')
source = source.replace('property bool hovered: false', 'property bool hovered: false\n    property bool testMicMuted: false')
source = source.replace('readonly property bool micMuted: !!shell.source?.audio?.muted', 'readonly property bool micMuted: testMicMuted || !!shell.source?.audio?.muted')
path.write_text(source)
path = path.with_name('AlbumArt.qml')
source = path.read_text().replace('function load() {', '''function testState() {
        return [first, second].map(image => ({opacity: image.opacity, status: image.status,
            width: image.sourceSize.width, height: image.sourceSize.height}));
    }
    function load() {''')
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
directory = Path(__file__).parent
with (directory / 'action-events').open('a') as log:
    log.write('start:' + action + '\n')
if action.startswith('brightness-'):
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
elif action == 'screenshot-region':
    time.sleep(1)  # A pending region selection must not block lock requests.
elif action == 'lock' and (directory / 'fail-lock').exists():
    result.update(ok=False, error={'message': 'Lock failed in test'})
print(json.dumps(result))
with (directory / 'action-events').open('a') as log:
    log.write('done:' + action + '\n')
sys.exit(0 if result['ok'] else 1)
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
        sleep 0.1
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
# Lock bypasses the normal queue, preserves its order, and reports failures.
events = directory / 'action-events'
before = len(events.read_text().splitlines())
ipc('testBrightnessInputs', quote(json.dumps([['screenshot-region'], ['nightlight-status']]), safe=''))
ipc('lock')
deadline = time.monotonic() + 3
while 'start:lock' not in events.read_text().splitlines()[before:]:
    assert time.monotonic() < deadline, 'Lock did not start'
    time.sleep(.02)
assert 'done:screenshot-region' not in events.read_text().splitlines()[before:], 'Lock waited for the screenshot'
while json.loads(ipc('status'))['desktopBusy']:
    assert time.monotonic() < deadline, 'Dispatch did not finish'
    time.sleep(.05)
assert events.read_text().splitlines()[before:] == ['start:screenshot-region', 'start:lock', 'done:lock',
        'done:screenshot-region', 'start:nightlight-status', 'done:nightlight-status']
(directory / 'fail-lock').touch()
ipc('lock')
deadline = time.monotonic() + 2
while json.loads(ipc('status'))['desktopBusy']:
    assert time.monotonic() < deadline
    time.sleep(.02)
assert json.loads(ipc('status'))['desktopError'] == 'Lock failed in test'
(directory / 'fail-lock').unlink()
ipc('lock')
time.sleep(.2)
assert not json.loads(ipc('status'))['desktopError']
PY
python3 - "$island_temp" <<'PY'
import json, os, subprocess, sys, time
from pathlib import Path
from urllib.parse import quote
directory = Path(sys.argv[1])
def ipc(target, method, *args):
    result = subprocess.check_output(['qs', '-p', str(directory), 'ipc', 'call', target, method, *args], text=True)
    if method in ('capture', 'captureMenu'):
        deadline = time.monotonic() + 2
        while not Path(args[0]).exists():
            assert time.monotonic() < deadline, 'Screenshot was not saved'
            time.sleep(.02)
    return result
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
assert layout['width'] == 320 and layout['height'] == 104 and not layout['mediaVisible'], layout
playing = {'identity': 'Music', 'isPlaying': True, 'playbackState': 1,
           'trackTitle': 'An evening on the coast — music for the long journey home', 'trackAlbum': 'Quiet places',
           'trackArtist': 'Example artist', 'canTogglePlaying': True,
           'canGoNext': True, 'canGoPrevious': True, 'canPlay': True,
           'canSeek': True, 'lengthSupported': True, 'positionSupported': True,
           'length': 240, 'position': 35,
           'trackArtUrl': str(directory / 'wallpaper-0.svg')}
ipc('island', 'testPlayer', quote(json.dumps([playing]), safe=''))
time.sleep(.5)
layout = json.loads(ipc(view, 'testLayout'))
assert layout['mediaTop'] >= 19.5 and layout['mediaBottom'] <= layout['height'] - 19.5, layout
assert abs(layout['artworkCenter'] - layout['height'] / 2) <= 1, layout
assert layout['mediaVisible'] and layout['seekVisible'] and layout['seekEnabled'] and layout['positionTimer'] and layout['artAvailable'], layout
for value, expected in [(120, 120), (-5, 0), (999, 240)]:
    assert float(ipc('island', 'testSeek', str(value))) == expected
if os.environ.get('ISLAND_CAPTURE_SCREEN'):
    ipc(view, 'capture', str(directory / 'media-playing.png'))
other = dict(playing, identity='Second player', isPlaying=False, playbackState=2,
             dbusName='other', canSeek=False, trackArtUrl=str(directory / 'wallpaper-1.svg'))
ipc('island', 'testPlayer', quote(json.dumps([playing, other]), safe=''))
ipc(view, 'testPlayerPopup', 'true')
time.sleep(.2)
assert geometry()['popupOpen'], geometry()
layout = json.loads(ipc(view, 'testLayout'))
menu = layout['menu']
assert menu['x'] >= 20 and menu['y'] >= 20 and menu['x'] + menu['width'] <= layout['width'] - 20 and menu['y'] + menu['height'] <= layout['height'] - 20, layout
if os.environ.get('ISLAND_CAPTURE_SCREEN'):
    ipc(view, 'captureMenu', str(directory / 'player-menu.png'))
ipc(view, 'testPlayerPopup', 'false')
ipc(view, 'testSelectPlayer', '2')
deadline = time.monotonic() + .5
while True:
    art = json.loads(ipc(view, 'testLayout'))['art']
    if all(0 < image['opacity'] < 1 for image in art): break
    assert time.monotonic() < deadline, ('Artwork did not crossfade', art)
    time.sleep(.01)
time.sleep(.4)
state = json.loads(ipc('island', 'status'))
assert state['player'] == 'Second player' and state['preferredPlayer'] == 'other', state
layout = json.loads(ipc(view, 'testLayout'))
assert layout['seekVisible'] and not layout['seekEnabled'] and not layout['positionTimer'], layout
assert all(image['width'] <= 224 and image['height'] <= 224 for image in layout['art']), layout
assert float(ipc('island', 'testSeek', '120')) == 35
ipc(view, 'testSelectPlayer', '0')
assert json.loads(ipc('island', 'status'))['player'] == 'Music'
unsupported = dict(playing, positionSupported=False, lengthSupported=False)
ipc('island', 'testPlayer', quote(json.dumps([unsupported]), safe=''))
time.sleep(.1)
layout = json.loads(ipc(view, 'testLayout'))
assert not layout['seekVisible'] and not layout['positionTimer'], layout
assert float(ipc('island', 'testSeek', '120')) == 35
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
python3 - "$island_temp" "$island_view" <<'PY'
import json, os, subprocess, sys, time
from pathlib import Path
directory, view = Path(sys.argv[1]), sys.argv[2]
def ipc(target, method, *args):
    return subprocess.check_output(['qs', '-p', str(directory), 'ipc', 'call', target, method, *args], text=True)
def state(): return json.loads(ipc('island', 'status'))
def layout(): return json.loads(ipc(view, 'testLayout'))
def send(title, *options):
    return subprocess.check_output(['notify-send', '--print-id', '--app-name=Island check', *options, title, 'Plain text <b>stays plain</b>'], text=True).strip()
def capture(name):
    if os.environ.get('ISLAND_CAPTURE_SCREEN'):
        target = directory / (name + '.png')
        ipc(view, 'capture', str(target))
        deadline = time.monotonic() + 2
        while not target.exists():
            assert time.monotonic() < deadline, 'Screenshot was not saved'
            time.sleep(.02)
ipc('island', 'close')
send('Notification test', '-t', '1000')
time.sleep(.5)
assert state()['notice'] == 'Notification test' and state()['unread'] == 1, state()
assert layout()['compactNotice'] and layout()['height'] == 38, layout()
capture('notice-compact')
ipc(view, 'testHover', 'true')
time.sleep(1.2)
assert state()['notice'] == 'Notification test' and layout()['height'] > 38, (state(), layout())
capture('notice-expanded')
ipc(view, 'testHover', 'false')
time.sleep(1.5)
assert not state()['notice'], state()
send('Persistent test', '-u', 'critical', '-t', '1')
time.sleep(1.2)
assert state()['notice'] == 'Persistent test', state()
capture('notice')
send('Transient test', '-h', 'boolean:transient:true', '-t', '1000')
send('Queued test', '-t', '1000')
time.sleep(1.2)
assert state()['notice'] == 'Persistent test' and state()['pendingNotices'] == 3, state()
history = json.loads(ipc('island', 'testHistory'))
assert [item['title'] for item in history] == ['Queued test', 'Persistent test', 'Notification test'], history
ipc(view, 'testHover', 'true')
ipc(view, 'testHover', 'false')
time.sleep(.7)
assert layout()['height'] == 38 and state()['notice'] == 'Persistent test', (layout(), state())
ipc('island', 'close')
assert state()['notice'] == 'Transient test', state()
time.sleep(1.2)
assert state()['notice'] == 'Queued test', state()
time.sleep(1.2)
assert not state()['notice'] and state()['pendingNotices'] == 0, state()
# Critical arrivals preempt a regular no-expiry notification without destroying it.
send('Retained test', '-t', '0')
send('Preemption test', '-u', 'critical', '-t', '0')
assert state()['notice'] == 'Preemption test' and state()['pendingNotices'] == 2, state()
ipc('island', 'close')
assert state()['notice'] == 'Retained test', state()
ipc('island', 'close')
ipc('island', 'testDnd', 'true')
send('DND test', '-t', '1000')
assert not state()['notice'], state()
send('DND critical test', '-u', 'critical', '-t', '0')
assert state()['notice'] == 'DND critical test', state()
ipc('island', 'close')
ipc('island', 'testDnd', 'false')
# Replacements reuse the same Quickshell object and must refresh history/timeouts.
replacement = send('Replace before', '-t', '1000')
time.sleep(.4)
assert send('Replace after', '-r', replacement, '-t', '2000') == replacement
time.sleep(1)
assert state()['notice'] == 'Replace after' and state()['pendingNotices'] == 1, state()
history = json.loads(ipc('island', 'testHistory'))
assert history[0]['title'] == 'Replace after' and all(item['title'] != 'Replace before' for item in history), history
ipc('island', 'close')
first = send('First queued', '-t', '0')
second = send('Second queued', '-t', '0')
send('Promoted replacement', '-r', second, '-u', 'critical', '-t', '0')
time.sleep(.1)
assert state()['notice'] == 'Promoted replacement' and state()['pendingNotices'] == 2, state()
send('Demoted replacement', '-r', second, '-u', 'normal', '-t', '0')
time.sleep(.1)
assert state()['notice'] == 'First queued', state()
send('Transient replacement', '-r', second, '-u', 'critical', '-t', '0', '-h', 'boolean:transient:true')
time.sleep(.1)
history = json.loads(ipc('island', 'testHistory'))
assert all(item['notificationId'] != int(second) for item in history), history
for notification_id, expected in [(second, 'First queued'), (first, '')]:
    subprocess.run(['dbus-send', '--session', '--print-reply', '--dest=org.freedesktop.Notifications',
                    '/org/freedesktop/Notifications', 'org.freedesktop.Notifications.CloseNotification',
                    'uint32:' + notification_id], check=True, stdout=subprocess.DEVNULL)
    assert state()['notice'] == expected, state()
single = send('Promoted current', '-t', '0')
ipc(view, 'testHover', 'true')
ipc(view, 'testHover', 'false')
time.sleep(.7)
assert layout()['height'] == 38, layout()
send('Promoted current', '-r', single, '-u', 'critical', '-t', '0')
time.sleep(.5)
assert layout()['height'] > 38, layout()
ipc('island', 'close')
time.sleep(.5)
assert layout()['statusWidth'] > 0 and state()['unread'] > 0, (layout(), state())
before = layout()['width']
ipc(view, 'testMicMuted', 'true')
time.sleep(.5)
assert layout()['micMuted'] and layout()['width'] > before, layout()
assert layout()['clockRight'] < layout()['statusLeft'], layout()
capture('unread-mic-muted')
ipc('island', 'notifications')
assert state()['unread'] == 0, state()
ipc(view, 'testMicMuted', 'false')
ipc('island', 'close')
time.sleep(.5)
assert layout()['width'] == 150 and not layout()['positionTimer'], layout()
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
