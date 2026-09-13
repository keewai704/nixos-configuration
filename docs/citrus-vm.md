# Citrus on Hyper-V

`citrus-vm` imports Citrus's desktop and Home Manager configuration, then
replaces physical hardware integration with Hyper-V guest support. It is a
separate deployment target; never activate `citrus` on this VM.

The VM uses Generation 2 UEFI, systemd-boot, a standard NixOS kernel, synthetic
storage/network/display drivers, and an ext4 disk labelled `nixos` with an EFI
partition labelled `ESP`. It does not mount Citrus's physical disks or load
NVIDIA, fingerprint-reader, or iPad device services. The shared Japanese
environment, applications, Hyprland, and Dynamic Island are retained.

Dynamic Island is fetched from the private `keewai704/hypr-island` repository
on `main`. Its pinned revision and source hash are unchanged from Citrus's
former local checkout. The Apple Music source is also private. Normal online
flake fetching therefore needs GitHub access to these repositories.

The local `pkgs/millennium-steam` recipe keeps the pinned Millennium and Bun
versions, but fixes Bun's dependency layout to `hoisted`. This avoids the
isolated linker's reported [non-reproducible dependency symlinks](https://github.com/oven-sh/bun/issues/30209)
that can cause fixed-output hash mismatches. Workspace manifests and the TTC
Rollup path are adjusted for that layout; Steam and Millennium remain enabled.

## Build and create the VM

On a Linux build environment with KVM available:

```console
nix build .#checks.x86_64-linux.citrus-vm --no-write-lock-file
nix build .#nixosConfigurations.citrus-vm.config.system.build.hypervImage --no-write-lock-file
```

Place the generated VHDX at `D:\Hyper-V\citrus-vm\citrus-vm.vhdx`. Create a
Generation 2 VM named `citrus-vm` with four virtual CPUs, 8 GiB startup memory
(4–8 GiB dynamic memory), and the internal Hyper-V Default Switch. Disable
Secure Boot for the unsigned NixOS boot chain. The virtual disk capacity is
128 GiB and the VHDX grows as space is used.
The image builder raises `cptofs`'s internal kernel memory from 100 MiB to 1 GiB
to populate this desktop image. This does not change the guest's RAM setting.

The desktop uses Mesa software rendering with expensive Hyprland effects
disabled and Dynamic Island's reduced-motion setting enabled. GPU passthrough
is not configured. A VM-only Aquamarine patch uses its existing GBM renderer
for the synthetic display and skips unsupported hardware color matrices.
Hyprpaper is pinned to 0.7.6, which can draw wallpapers through shared memory
without a GPU render node. A small CLI adapter lets Dynamic Island keep its
wallpaper selection and restoration using that version's text IPC.
Hardware brightness, Bluetooth, audio devices, and hardware color-temperature
adjustment are unavailable in this basic Hyper-V console configuration.

## Access and deployment

The account remains `keewai`. `access.nix` contains only the public key for this
VM; its private key is kept on the Windows host. SSH accepts keys only. Set a
login password with `passwd` after the initial SSH connection before using
Hyprlock. Tailscale authentication is a separate first-login action.

Copy the configuration checkout to `/home/keewai/nixos-configuration`, then
follow the repository's test, health-check, and switch workflow using
`--flake .#citrus-vm`. Check `hostnamectl --static`, `/etc/hostname`, networking,
`sshd`, `greetd`, and the user desktop session. Confirm that the running and
boot-default system links agree after switching and rebooting.

After a fresh graphical login, run `bash checks/citrus-vm-desktop.sh` as `keewai`
to check services, networking, monitor state, wallpaper IPC, and renderer errors.
