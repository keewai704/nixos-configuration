# Dynamic Island for citrus

An independent Quickshell recreation of saneAspect's public Dynamic Island demo.
UI labels are English; media titles and notification text retain their original language.

Reference: [I Replaced My Whole Hyprland Bar With One Notch](https://www.youtube.com/watch?v=nKomstQedmE).
The video was inspected through its full English transcript and extracted frames.

| Reference | Implemented behavior |
| --- | --- |
| 3:03–4:29 | Black 150 × 38 resting pill, clock, four playback bars; 11px floating gap; switchable notch with concave 14px shoulders. |
| 4:56–7:25 | One continuous outline; rounded top corners flatten before the notch shoulders grow; 4px top overshoot. |
| 7:29–10:10 | Hover to expand, click to pin, left media card with 88px artwork and transport, clock moving right, seven-day date carousel. |
| 10:12–11:08 | 400ms damped spring (ratio 0.8) for geometry; critically damped opacity. |
| 11:15–14:26 | Live, persistent appearance controls; font uses the creator's suggested Inter alternative. |

[The September update](https://www.youtube.com/watch?v=rLFFjT6kAkA&t=613s) was also checked:
it identifies the original shell as Dynamite and describes its dotfiles as a paid-course bonus.
No original private source or paid assets are included here.

The pill expands into media, app search, calendar, notification history, controls,
settings and a session menu. Audio uses PipeWire directly; playback uses MPRIS and
honors each player's supported operations. Notification text is always plain text.
History retains the most recent 50 notifications for the current session.
The four animated bars indicate playback; they are not a measured audio spectrum.

Noctalia's bar, notification daemon and OSD are disabled to avoid duplicates.
Its existing wallpaper, lock screen, Polkit agent, clipboard, window switcher and
hardware detail panels remain available. Hardware detail buttons open those panels.
The video's separate full settings app, custom lock screen and whole-screen corner
masks are outside this Island implementation.

## Controls

- Hover to expand; click empty space to pin/unpin. Right-click or Escape to close.
- Scroll over the pill for volume; click the clock/date for the calendar.
- `Super+D`: media; `Super+Space`: apps; `Super+I`: controls; `Super+N`: history.
- `Super+Shift+Z`: Island settings; `Super+Alt+C`: session menu.
- `islandctl [toggle|launcher|calendar|controls|notifications|settings|session|close|notch|status]`.
- Settings persist in `~/.local/state/dynamic-island.ini`.
- The native notification server honors explicit no-expiry and critical urgency;
  other notifications expire after the application's timeout (6s by default).

## Checks

```sh
nix shell nixpkgs#nodejs -c node hosts/citrus/dynamic-island/check-geometry.js
nix shell nixpkgs#quickshell nixpkgs#dbus nixpkgs#libnotify nixpkgs#python3 -c bash hosts/citrus/dynamic-island/check-runtime.sh
```

The runtime check requires a local Wayland session. It uses an isolated D-Bus
session, temporary settings and a copied configuration; it never replaces the
running desktop's notification server. Test logs remain under `/tmp/island-check.*`.
