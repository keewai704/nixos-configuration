#!/usr/bin/env bash
# Run with the screen unlocked and no finger on the reader.
set -euo pipefail

runtime_host=$(hostnamectl --static 2>/dev/null || hostname)
test "$runtime_host" = "$(cat /etc/hostname)"
test "$runtime_host" = citrus
cd -- "$(dirname -- "$0")/../.."

driver_derivation=$(nix eval --raw --no-write-lock-file \
  .#nixosConfigurations.citrus.config.services.fprintd.package.buildInputs \
  --apply 'inputs: (builtins.head (builtins.filter (p: (p.pname or "") == "libfprint") inputs)).drvPath')
driver_runtime=$(nix build --no-link --print-out-paths "${driver_derivation}^out")
gjs_runtime=$(nix build --no-link --no-write-lock-file --print-out-paths \
  .#nixosConfigurations.citrus.pkgs.gjs)
typelib_paths=
while IFS= read -r package_path; do
  if test -d "$package_path/lib/girepository-1.0"; then
    typelib_paths+="$package_path/lib/girepository-1.0:"
  fi
done < <(nix-store --query --requisites "$driver_runtime" "$gjs_runtime")

sudo env GI_TYPELIB_PATH="$typelib_paths" G_DEBUG=fatal-criticals timeout 20 "$gjs_runtime/bin/gjs" -c "$(cat <<'JS'
imports.gi.versions.FPrint = "2.0";
const {FPrint, Gio, GLib} = imports.gi;
const context = new FPrint.Context();
context.enumerate();
const device = context.get_devices().find(device => device.get_driver() === "cs9711");
if (!device) throw new Error("CS9711 reader not detected");
for (const delay of [10, 100, 1000, 1000]) {
    device.open_sync(null);
    const cancel = new Gio.Cancellable();
    GLib.timeout_add(GLib.PRIORITY_DEFAULT, delay, () => {
        cancel.cancel();
        return GLib.SOURCE_REMOVE;
    });
    try {
        device.capture_sync(true, cancel);
        throw new Error("Keep your finger off the reader during this check");
    } catch (error) {
        if (!error.matches?.(Gio.io_error_quark(), Gio.IOErrorEnum.CANCELLED)) throw error;
    } finally {
        device.close_sync(null);
    }
    print(`Capture cancelled after ${delay} ms; device closed successfully`);
}
JS
)"
