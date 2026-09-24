# Session control

Read through cleanup before starting. Follow the skill's transport, authorization,
privacy, and exclusive-use boundaries throughout the session.

## Start one persistent helper

Use a private FIFO and transient systemd user service so the helper survives tool
calls. An advisory lock under `XDG_RUNTIME_DIR` rejects a second helper but not
other applications such as Omarchy's viewer. Close other controllers first:
cleanup stops all media streams on the selected device. Do not reconnect for
every action. If the user manager is unavailable, report the limitation; do not
substitute a root service or invent a terminal-session API.

Choose the authorized mode before starting; this example uses USB. Change
`connection` to `auto` or `wifi` only when appropriate. Omit `--serial` and its
argument only when automatic selection of the sole device/record is intended.

```sh
set -e
umask 077
session=$(mktemp -d "${XDG_RUNTIME_DIR:?}/apple-device-usb.XXXXXX")
unit="apple-device-usb-${session##*.}"
connection=usb
mkfifo "$session/input"
systemd-run --user --unit="$unit" --collect \
  --property=UMask=0077 \
  --property="StandardOutput=append:$session/events.jsonl" \
  --property="StandardError=append:$session/stderr.log" \
  "$(command -v bash)" -c \
  'exec 3<>"$1/input"; exec "$2" --connection "$3" --serial "$4" <&3' \
  _ "$session" "$(command -v apple-device-usb)" "$connection" '<observed-identifier>'
printf 'session=%s\nunit=%s\n' "$session" "$unit"
```

Record the absolute session directory and unit name. Restore those literal values
in later calls; shell variables do not persist. The absolute Nix launcher path
is required because user services do not inherit the shell PATH.

Read complete new lines from `events.jsonl` with the available file-reading tool;
track consumed lines. The initial event reports actual `connection`,
`requested_connection`, private device identifiers, and `frame`, `image`, `size`,
`original`, `orientation`, and `touch_rotation`. Open `image` with the image tool
and use its pixel dimensions. The default longest edge is 1280px. Preview and
full-size captures remain under `~/Pictures/apple-device`, outside transient logs.

A launched unit is not a successful connection. Startup has a 90-second budget,
including tunnel and service setup. If no initial frame arrives, inspect only the
recorded unit's status and `stderr.log`. Do not relaunch while its state is unknown.

## Observe, act once, and inspect the result

Send one JSON line to the existing FIFO, then read its new response event:

```sh
systemctl --user is-active --quiet "$unit" &&
  timeout 5 bash -c 'printf "%s\n" "$2" >"$1/input"' \
    _ "$session" '{"shot":1280}'
```

The write confirms queuing, not execution. Account for the response before another
action. A timeout or missing response is not permission to replay: inspect logs
and session state first. A fresh shot can queue behind an unfinished action; it
is not a cancellation mechanism.

Replace the JSON argument with one intended command. These are independent
examples, not a sequence. Use the latest inspected `frame` and actual target
coordinates, not the example values:

| Command | Effect |
| --- | --- |
| `{"shot":1280}` | Refresh without input; `{"shot":0}` returns full size. Maximum edge: 4096. |
| `{"frame":1,"tap":[240,180]}` | Tap an image pixel after verifying touch mapping. |
| `{"frame":2,"drag":[900,700,900,300]}` | Touch-contact drag, about 0.6 seconds; upstream `swipe` is pointer motion. |
| `{"frame":3,"type":"hello"}` | ASCII keyboard HID using the active device layout. |
| `{"frame":4,"key":[227,4]}` | Simultaneous HID chord, here Cmd+A. Enter: `[40]`; Backspace: `[42]`; Escape: `[41]`. Accepts 1–6 HID codes in 4–231. |
| `{"frame":5,"paste":"日本語"}` | Replace the device clipboard and send Cmd+V. |
| `{"frame":6,"home":true}` | Hardware Home-button event, not a swipe. |

Select and verify the intended text field before typing or pasting. Batch a known
string or chord in one command; `type` and `paste` accept 1–1000 characters. Paste
is explicit, not clipboard synchronization, and may require app/device permission.
Do not overwrite the clipboard without task authorization or put typed/clipboard
contents in diagnostic reports.

Successful input releases keys/touches and returns the next screenshot. Inspect
it before a dependent action: `sent` means dispatched, not visually successful.
If animation or small text prevents verification, request another shot and use
its new frame and dimensions. Do not stream video or capture per keystroke.

### Touch mapping

Old frames, out-of-bounds coordinates, and changed display geometry are rejected.
For **iPad17,3 / landscapeLeft**, image-normalized `(u,v)` maps automatically to
HID `(1-v,u)`. For other model/orientation combinations, use a frame-bound
`{"frame":1,"calibrate":90}` with the appropriate 0/90/180/270-degree clockwise
rotation from image to HID. Calibration returns an acknowledgement, not a new
image or proof of correctness. Verify a harmless off-center target before
consequential input; never guess using destructive controls. Recheck after
rotation or display changes. MPV's normalized video coordinates do not establish
this screenshot mapping.

## Close the helper and media session

Send `{"quit":true}` through the same FIFO. Confirm the new `closed` event and
inactive service before removing only the recorded temporary session directory.
Normal exit releases input, requests media shutdown, then closes owned receiver
tasks, media/display resources, and finally the tunnel. On pymobiledevice3
11.15.5, `DisplayService.stop_all_streams(rsd)` opens a fresh display connection;
reusing the start connection or passing the session UUID to `stop_media_stream`
is invalid. This stops all media streams on the selected device, requiring
exclusive use. Cleanup failures report an error, not `closed`.

SIGINT/SIGTERM request the same context cleanup. If stuck, stop the exact recorded
unit with `systemctl --user stop "$unit"`, inspect logs, and confirm it is inactive.
Do not claim graceful close without the event. `closed` confirms local cleanup,
not the remote service's state. Keep the shared `apple-device-usb.lock` file;
closing its descriptor releases the lock.

Captures are not deleted with session logs. Keep task-needed captures under the
user's retention instructions; never delete unrelated images. Report only
visually verified operations, show relevant captures using absolute paths, and
distinguish setup, screenshot, input, and cleanup results.
