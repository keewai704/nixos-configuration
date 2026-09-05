#!/usr/bin/env bash
# nix shell nixpkgs#{sway,hyprlock} -c bash check-lock.sh /path/to/hyprlock.conf
set -euo pipefail
island_config=$(realpath "${1:?Pass the generated hyprlock.conf}")
island_temp=$(mktemp -d /tmp/island-lock.XXXXXX)
mkdir -m 700 "$island_temp/runtime"
cat > "$island_temp/sway.conf" <<'CONF'
output * resolution 1280x720
xwayland disable
CONF
island_lock_pid=
island_sway_pid=
cleanup() {
    [[ -z $island_lock_pid ]] || kill "$island_lock_pid" 2>/dev/null || true
    [[ -z $island_sway_pid ]] || kill "$island_sway_pid" 2>/dev/null || true
    [[ -z $island_lock_pid ]] || wait "$island_lock_pid" 2>/dev/null || true
    [[ -z $island_sway_pid ]] || wait "$island_sway_pid" 2>/dev/null || true
}
trap cleanup EXIT
# The private runtime directory makes it impossible to lock the real desktop.
env -u WAYLAND_DISPLAY -u DISPLAY -u SWAYSOCK \
    XDG_RUNTIME_DIR="$island_temp/runtime" WLR_BACKENDS=headless \
    WLR_HEADLESS_OUTPUTS=1 WLR_RENDERER=pixman \
    sway --unsupported-gpu --config "$island_temp/sway.conf" --debug \
    > "$island_temp/sway.log" 2>&1 &
island_sway_pid=$!
island_display=
for ((attempt=0; attempt<50; attempt++)); do
    for island_socket in "$island_temp/runtime"/wayland-*; do
        if [[ -S $island_socket ]]; then island_display=$island_socket; break; fi
    done
    [[ -z $island_display ]] || break
    sleep 0.1
done
test -n "$island_display"
env XDG_RUNTIME_DIR="$island_temp/runtime" LIBGL_ALWAYS_SOFTWARE=1 \
    hyprlock --display "$island_display" --config "$island_config" \
    --immediate-render --no-fade-in --verbose > "$island_temp/lock.log" 2>&1 &
island_lock_pid=$!
sleep 3
kill -0 "$island_lock_pid"
if rg -i 'config error|config option.*does not exist|failed to lock|invalid config' "$island_temp/lock.log"; then
    exit 1
fi
rg 'onLockLocked called' "$island_temp/lock.log"
echo "Isolated lock check passed; logs: $island_temp"
