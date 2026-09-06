# Dynamic Island for citrus

An independent Quickshell recreation of saneAspect's public Dynamic Island demo.
UI labels are English; media titles and notification text retain their original language.

Reference: [I Replaced My Whole Hyprland Bar With One Notch](https://www.youtube.com/watch?v=nKomstQedmE).
The video was inspected through its full English transcript and extracted frames.

| Reference | Implemented behavior |
| --- | --- |
| 3:03–4:29 | Black 150 × 38 resting pill, clock, four playback bars; 11px floating gap; switchable notch with concave 14px shoulders. |
| 4:56–7:25 | One continuous outline; rounded top corners flatten before the notch shoulders grow; 4px top overshoot. |
| 7:29–10:10 | Hover to expand, pointer leave to collapse; centered artwork and transport, clock moving right, seven-day date carousel. |
| 10:12–11:08 | 400ms damped spring (ratio 0.8) for geometry; critically damped opacity. |
| 11:15–14:26 | Persistent appearance controls; text, accents, surfaces and font follow the system's Stylix theme. The shell background stays pure black. |

[The September update](https://www.youtube.com/watch?v=rLFFjT6kAkA&t=613s) was also checked:
it identifies the original shell as Dynamite and describes its dotfiles as a paid-course bonus.
No original private source or paid assets are included here.

The pill expands into media, app search, calendar, notification history, controls,
settings and a session menu. Audio uses PipeWire directly; playback uses MPRIS and
honors each player's supported operations. Notification text is always plain text.
History retains the most recent 50 non-transient notifications for the current
session. The resting pill shows an unread count and microphone-mute indicator
only when needed; opening History marks its entries as read.
The four animated bars indicate playback; they are not a measured audio spectrum.

Noctalia is no longer installed or started by the Citrus configuration. The Island
provides the bar, notifications, OSD, app launcher, wallpaper picker, searchable
clipboard history, window switcher, calendar and desktop controls.

| Function | Implementation |
| --- | --- |
| Display brightness | DDC/CI on external monitors; `brightnessctl` for laptop backlights. The slider and keys adjust real hardware brightness in 5% steps. |
| Wallpaper | Image previews, local file picker and Hyprpaper; the selected path survives login. Add images to `~/Pictures/Wallpapers`. |
| Lock and idle | Hyprlock with PAM authentication, clock and blurred background. Hypridle locks after 10 minutes, turns displays off after 11 minutes, and waits for the lock notification before sleep. |
| Clipboard | Cliphist stores text and images; search, copy, delete one item or clear history from the Island. |
| Window switching | Search open windows by title or application, then press Enter to focus one. |
| Network and Bluetooth | Native NetworkManager/Blueman applets provide connection and pairing agents; detailed settings open from Controls. |
| Audio and media | PipeWire output/microphone sliders and mute; MPRIS transport; Pavucontrol for routing and devices. |
| Capture | Region, active window and all-screen captures through Grimblast. |
| Night light and power | Hyprsunset toggle, available power profiles, lock/suspend/restart/power-off actions. |
| Authentication | Hyprpolkitagent provides permission prompts independently of the Island process. |

The lock timing uses [Hypridle's lock-notification mode](https://wiki.hypr.land/Hypr-Ecosystem/hypridle/).
The video's separate full settings app and whole-screen corner masks are outside
this Island implementation.

The media player's menu selects an application or Automatic mode. A chosen player
stays selected until it disappears or Automatic is selected. Position and remaining
time appear only when the player supplies them; seeking also requires `canSeek`.
Position updates run once per second only while playing in the expanded media view.
With no active or paused track, the expanded Island becomes a smaller clock/date
panel. Album art crossfades over 200 ms and loads at its display pixel size; reduced
motion disables the fade. The clock itself updates once per minute.

Normal notifications first show a compact icon and summary; hover or click to read
the details. Their timeout starts when they reach the front and pauses while reading
or using another page. Critical notifications expand immediately and remain until
dismissed or closed by the sender. They preempt regular notifications without
destroying them; regular notifications then resume in arrival order. Leaving folds
the details back into the preview. Replacements refresh the existing queue entry,
history, urgency and timeout when their properties change. Quickshell 0.3.0 does not
signal replacements with entirely unchanged properties, so those cannot reset the
timeout. Transient notifications skip history, including when an existing entry is
replaced as transient.

Lock requests use an independent process, so they run immediately even while the
Island is waiting for a screenshot selection or a slow hardware operation.

## Controls

- Hover to expand; leaving for 160 ms collapses the panel, including pages opened
  by clicking or shortcuts. A shortcut stays open for keyboard use until the
  pointer enters and leaves. File pickers and tray menus keep the panel open
  while they are in use. Right-click or Escape closes immediately.
- Scroll over the pill for volume; click the clock/date for the calendar.
- `Super+D`: media; `Super+Space`: apps; `Super+I`: controls; `Super+N`: history.
- `Super+Z` / `Super+Shift+Z`: Island settings; `Super+Alt+C`: session menu.
- `Alt+[` / `Alt+]`: lower/raise brightness; hardware brightness keys also work.
  Repeats and slider moves are folded into the latest target while the monitor is
  busy, preserving direction changes at 0/100%. A continuous burst reuses the
  detected DDC bus; failed requests discard queued repeats so the next press can retry.
- `Super+Shift+Space`: wallpapers; `Super+V`: clipboard; `Alt+Tab`: windows.
- `Super+Alt+L`: lock; `Print`: region; `Ctrl+Print`: active window; `Shift+Print`: all screens.
- Media and volume hardware keys route to the Island, including while locked.
- `islandctl [toggle|launcher|calendar|controls|notifications|settings|session|wallpaper|clipboard|windows|lock|close|notch|status]`.
- `island-action help` lists native actions; brightness commands accept `--bus`, `--display` and `--step` for explicit hardware selection or calibration.
- Settings persist in `~/.local/state/dynamic-island.ini`.
- The background is fixed at `#000000`. Other colors and typography come from
  Stylix through the Quickshell service's `ISLAND_THEME` environment. Local accent
  overrides are no longer used. Icons use centered vector paths; expanded panels have
  20 px content margins and controls use symmetric padding.
- The native notification server honors explicit no-expiry and critical urgency;
  other notifications expire after the application's timeout (6s by default).

## Checks

```sh
nix shell nixpkgs#nodejs -c node hosts/citrus/dynamic-island/check-geometry.js
nix shell nixpkgs#python3 -c python3 -B hosts/citrus/dynamic-island/check-actions.py
nix shell nixpkgs#quickshell nixpkgs#dbus nixpkgs#libnotify nixpkgs#python3 -c bash hosts/citrus/dynamic-island/check-runtime.sh
nix shell nixpkgs#sway nixpkgs#hyprlock -c bash hosts/citrus/dynamic-island/check-lock.sh ~/.config/hypr/hyprlock.conf
```

The runtime check requires a local Wayland session. It uses an isolated D-Bus
session, temporary settings and a copied configuration; it never replaces the
running desktop's notification server. Test logs remain under `/tmp/island-check.*`.
It checks hover exit/re-entry, popup handling, equal panel margins and list bounds.
It also covers notification priority, replacements, transient history, unread/mic
badges, player selection, seek guards, artwork crossfades and the compact idle view.
Fake actions also verify that locking bypasses a slow capture
and reports failures without disturbing the ordinary action queue.
Set `ISLAND_CAPTURE_SCREEN=DP-1` to save screenshots of each page and media state.
Run `nix shell nixpkgs#python3 nixpkgs#wlrctl -c python3 hosts/citrus/dynamic-island/check-native-hover.py` against the running
island to check real pointer entry and exit. It briefly moves the pointer and
opens Controls, then restores the pointer position.
The lock check uses a separate headless compositor and private Wayland socket;
it verifies configuration and lock acquisition without locking the real desktop
or attempting password authentication. Logs remain under `/tmp/island-lock.*`.
