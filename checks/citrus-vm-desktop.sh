#!/usr/bin/env bash
set -euo pipefail

# Run as keewai on the Hyper-V guest after test/switch and a fresh login.
test "$(hostnamectl --static)" = citrus-vm
test "$(cat /etc/hostname)" = citrus-vm
test "$(id -un)" = keewai
test -z "$(systemctl --failed --no-legend)"
test -z "$(systemctl --user --failed --no-legend)"
for unit in sshd greetd; do
  systemctl is-active --quiet "$unit"
done
for unit in quickshell hyprpaper island-wallpaper-restore; do
  systemctl --user is-active --quiet "$unit"
done
curl --fail --silent --show-error --max-time 15 https://cache.nixos.org/nix-cache-info >/dev/null

export HYPRLAND_INSTANCE_SIGNATURE
HYPRLAND_INSTANCE_SIGNATURE=$(systemctl --user show-environment | sed -n 's/^HYPRLAND_INSTANCE_SIGNATURE=//p')
test -n "$HYPRLAND_INSTANCE_SIGNATURE"
test -z "$(hyprctl configerrors)"
hyprctl -j monitors | grep -Eq '"disabled"[[:space:]]*:[[:space:]]*false'
island-action wallpaper-status | grep -q '"ok":true'
log="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/hyprland.log"
test -f "$log"
if grep -E 'no matching devices found|initMgpu: no renderer|failed to commit ctm: no ctm prop support' "$log"; then
  exit 1
fi
printf 'citrus-vm desktop, wallpaper, and network checks passed\n'
