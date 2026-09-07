# Package ownership audit

This is an audit of the package-ownership migration in the accompanying
configuration, compared with baseline commit
`ae9575ab7e8af8fbbe3edf89c20c48161e35fe5c`. The local runtime boundary was
verified as `citrus`: `hostnamectl --static` and `/etc/hostname` both return
`citrus`. The flake exposes both
`nixosConfigurations.citrus` and `nixosConfigurations.orange`; orange was
evaluated locally only, and no live Orange system was changed.

The configuration uses NixOS-integrated Home Manager with
`home-manager.useUserPackages = true`. The Home Manager package roots below
therefore remain part of the NixOS activation/profile and are not a separate
rootless deployment. This follows the NixOS [package-management
model](https://nixos.org/manual/nixos/unstable/#sec-package-management) and
Home Manager's [`home.packages` option](https://home-manager.dev/manual/unstable/options/home-manager/home.html).

## Evaluation method and counts

The inventory counts the evaluated option values:

- `config.environment.systemPackages`, after preserving list order.
- `config.home-manager.users.keewai.home.packages`, after preserving list
  order.
- “Raw” is the list length. “Unique” removes exact repeated derivation names.
  Repeated names are normal: NixOS modules add the same helper package through
  several integration paths.

| host | baseline system roots | current system roots | baseline Home Manager roots | current Home Manager roots |
| --- | ---: | ---: | ---: | ---: |
| citrus | 198 / 140 | 169 / 112 | 49 / 48 | 77 / 75 |
| orange | 143 / 85 | 141 / 83 | 0 / 0 | 10 / 10 |

Each count is `raw / unique`; baseline is the commit above and current is the
accompanying configuration. The migration removes personal roots from the NixOS system list
while preserving them in the user profile. Generated Home Manager roots also
move across the boundary, so the raw lists are not expected to have the same
shape.

The command used for a package list is:

```sh
runtime_host="$(hostnamectl --static 2>/dev/null || hostname)"
etc_host="$(tr -d '\r\n' < /etc/hostname)"
test "$runtime_host" = "$etc_host"

nix eval --json --no-write-lock-file \
  ".#nixosConfigurations.citrus.config.environment.systemPackages" \
  --apply '
    xs:
    let names = builtins.map (p: p.name or (p.pname or "unnamed")) xs;
    in names
  '

nix eval --json --no-write-lock-file \
  ".#nixosConfigurations.citrus.config.home-manager.users.keewai.home.packages" \
  --apply '
    xs:
    let names = builtins.map (p: p.name or (p.pname or "unnamed")) xs;
    in names
  '

# Replace citrus with orange for the other host.
```

The source-location query for system roots is:

```sh
nix eval --json --no-write-lock-file \
  ".#nixosConfigurations.citrus.options.environment.systemPackages.definitionsWithLocations"
```

For Home Manager, the direct declarations are in the repository files listed
in the inventory below. The effective Home Manager list also includes
generated roots from Home Manager and imported third-party modules; those
generated roots are grouped by their evaluated module source.

## Evaluated system package roots

The NixOS source paths in this section are relative to the locked nixpkgs
source. Duplicate roots are shown in the source group that defines them; the
host-level unique counts above deduplicate them.

The base operating-system tools remain globally available for administration,
recovery, and service use, including when the personal profile is unavailable.
Moving these module-provided tools would restrict those uses.

### Roots common to citrus and orange

| evaluated source module | roots |
| --- | --- |
| `nixos/modules/installer/tools/tools.nix` | `nixos-version`, `nixos-rebuild-ng-26.11`, `nixos-option-26.11`, `nixos-install`, `nixos-generate-config`, `nixos-enter`, `nixos-build-vms` |
| `nixos/modules/tasks/lvm.nix` | `lvm2-2.03.41` |
| `nixos/modules/tasks/filesystems.nix` | `dosfstools-4.2`, `mtools-4.0.49`, `e2fsprogs-1.47.4` |
| `nixos/modules/tasks/bcache.nix` | `bcache-tools-1.1` |
| `nixos/modules/system/boot/systemd.nix`, `modprobe.nix`, `kexec.nix` | `systemd-261.1`, `kmod-31`, `kexec-tools-2.0.32` |
| `nixos/modules/services/system/dbus.nix` | `dbus-1.16.2`, `dbus-broker-37` |
| `nixos/modules/services/networking/wpa_supplicant.nix`, `tailscale.nix`, `networkmanager.nix`, `modemmanager.nix`, `firewall.nix`, `firewall-iptables.nix` | `wpa_supplicant-2.11`, `tailscale-1.102.2`, `networkmanager-1.58.0`, `modemmanager-1.24.2`, `iptables-1.8.13`, `nixos-firewall-tool-26.11` |
| `nixos/modules/security/sudo.nix`, `polkit.nix`, `pam.nix` | `sudo-1.9.17p2`, `polkit-127`, `linux-pam-1.7.2` |
| `nixos/modules/programs/shadow.nix`, `nano.nix`, `less.nix` | `shadow-4.20.0`, `bash-interactive-5.3p15`, `nano-9.2`, `less-704` |
| `nixos/modules/misc/man-db.nix` | `man-db-2.13.1` |
| `nixos/modules/misc/documentation.nix` | `texinfo-interactive-7.2`, `nixos-configuration-reference-manpage`, `nixos-manual-html`, `nixos-help` |
| `nixos/modules/config/xdg/sounds.nix`, `mime.nix`, `icons.nix` | `sound-theme-freedesktop-0.8`, `shared-mime-info-2.4`, `hicolor-icon-theme-0.18` |
| `nixos/modules/config/users-groups.nix` | Repeated `shadow-4.20.0` and `bash-interactive-5.3p15` entries; these add no new unique root. |
| `nixos/modules/config/system-path.nix` | `bind-9.20.26`, `hostname-hostname-debian-3.25`, `iproute2-7.1.0`, `iputils-20250605`, `openssh-10.5p1`, `acl-2.4.0`, `attr-2.6.0`, `bzip2-1.0.8`, `coreutils-full-9.11`, `cpio-2.15`, `curl-8.21.0`, `diffutils-3.12`, `findutils-4.11.0`, `gawk-5.4.1`, `getent-glibc-2.42-67`, `getconf-glibc-2.42-67`, `gnugrep-3.12`, `patch-2.8`, `gnused-4.10`, `gnutar-1.35`, `gzip-1.14`, `xz-5.8.3`, `libcap-2.78`, `ncurses-6.6`, `libressl-4.3.2`, `mkpasswd-5.6.6`, `procps-4.0.6`, `time-1.10`, `util-linux-2.42.2`, `which-2.25`, `zstd-1.5.7`, `glibc-2.42-67`, `perl-5.42.0`, `rsync-3.4.4`, `strace-7.1` |
| `nixos/modules/config/resolvconf.nix` | `openresolv-3.17.4` |
| `nixos/modules/config/nix.nix` | `nix-2.34.8`, `nix-info`, `nix-bash-completions-0.6.8` |
| `nixos/modules/config/i18n.nix`, `fonts/fontconfig.nix`, `console.nix` | `glibc-locales-2.42-67`, `fontconfig-2.18.2`, `kbd-2.9.0` |

### Citrus-only system roots

These roots come from desktop, graphics, input, and hardware integrations
selected in [`hosts/citrus/default.nix`](../hosts/citrus/default.nix) and
[`hosts/citrus/desktop.nix`](../hosts/citrus/desktop.nix).

| evaluated source module | roots |
| --- | --- |
| `nixos/modules/tasks/filesystems.nix` | `xfsprogs-7.1.1` |
| `nixos/modules/services/security/fprintd.nix` | `fprintd-1.94.5` |
| `nixos/modules/services/misc/graphical-desktop.nix` | `nixos-icons-0-unstable-2025-06-28`, `xdg-utils-1.2.1` |
| `nixos/modules/services/hardware/udisks2.nix`, `power-profiles-daemon.nix`, `bluetooth.nix` | `udisks-2.11.2`, `power-profiles-daemon-0.30`, `bluez-5.87` |
| `nixos/modules/services/desktops/tumbler.nix`, `pipewire/wireplumber.nix`, `pipewire/pipewire.nix`, `gvfs.nix`, `gnome/gnome-keyring.nix`, `gnome/at-spi2-core.nix`, `blueman.nix`, `accessibility/speechd.nix` | `tumbler-4.20.2`, `wireplumber-0.5.15`, `pipewire-1.6.8`, `gvfs-1.60.2`, `gnome-keyring-50.0`, `at-spi2-core-2.60.6`, `blueman-2.4.6`, `speech-dispatcher-0.12.1` |
| `nixos/modules/security/rtkit.nix` | `rtkit-0.14` |
| `nixos/modules/programs/zsh/zsh.nix`, `xwayland.nix`, `wayland/uwsm.nix`, `wayland/hyprland.nix` | `zsh-5.9.2`, `nix-zsh-completions-0.5.1-unstable-2025-12-12`, `xwayland-24.1.13`, `uwsm-0.26.6`, `hyprland-0.56.0+date=2026-09-05_2eb5180` |
| `nixos/modules/programs/steam.nix` | `steam-1.0.0.85`, `steam-run-1.0.0.85` |
| `nixos/modules/programs/gamescope.nix`, `fuse.nix`, `dconf.nix` | `gamescope`, `fuse-2.9.9`, `fuse-3.18.2`, `dconf-0.49.0` |
| `nixos/modules/hardware/video/nvidia.nix` | `nvidia-x11-x86_64-unknown-linux-gnu-610.57.04`, `nvidia-settings-610.57.04` |
| `nixos/modules/config/xdg/portal.nix` | `xdg-desktop-portal-1.22.1`, `xdg-desktop-portal-hyprland-1.4.1+date=2026-08-29_ba31964`, `xdg-desktop-portal-gtk-1.15.3`; `gnome-keyring` and `hyprland` are repeated roots. |

The explicit NixOS module package lists contain no direct personal application
roots after the migration. NetworkManager remains a system daemon; only its
`network-manager-applet` GUI client is in the citrus Home Manager list. Blueman
remains system-owned because the NixOS `services.blueman` module provides its
package and D-Bus/systemd integration.

### Orange-only system roots

| evaluated source module | roots |
| --- | --- |
| `nixos/modules/services/network-filesystems/samba.nix` | `samba-4.23.10` |
| `nixos/modules/services/databases/redis.nix` | `redis-8.10.1` |
| `nixos/modules/services/databases/postgresql.nix` | `postgresql-and-plugins-17.11` |

### Migration delta

The following baseline system roots moved to the listed Home Manager owner in
the accompanying configuration. Package names include their evaluated versions where the
derivation supplies one.

| baseline system roots | current owner |
| --- | --- |
| `apple-music-client-0.2.0-400b2b4`, `alac-room-auth-service-0.0.2-20260710`, `chatgpt-desktop-26.901.41123`, `brightnessctl-0.5.1` | [`home/keewai/citrus/desktop.nix`](../home/keewai/citrus/desktop.nix) |
| `bitwarden-desktop-2026.8.0`, `pinentry-gnome3-1.3.2`, `island-bitwarden-setup` | [`home/keewai/citrus/bitwarden.nix`](../home/keewai/citrus/bitwarden.nix) |
| `pymobiledevice3` | [`home/keewai/citrus/ipad.nix`](../home/keewai/citrus/ipad.nix) |
| `ddcutil-2.2.7`, `grimblast-0.1-unstable-2026-06-30`, `network-manager-applet-1.36.0`, `pavucontrol-6.2`, `xarchiver-0.5.4.27` | [`home/keewai/citrus/desktop.nix`](../home/keewai/citrus/desktop.nix) |
| `brave-origin-1.94.117`, `pywalfox-native-2.9.0` | [`home/keewai/citrus/browser.nix`](../home/keewai/citrus/browser.nix) |
| `gws-0.22.5` | [`home/keewai/citrus/desktop.nix`](../home/keewai/citrus/desktop.nix) |
| `hazkey-settings-0.2.1` | [`home/keewai/citrus/input-method.nix`](../home/keewai/citrus/input-method.nix) via `nix-hazkey.homeModules.hazkey` |
| `git-2.55.0`, `ripgrep-15.2.0` | [`home/keewai/common.nix`](../home/keewai/common.nix) |
| `fcitx5-with-addons-5.1.21`, `gtk3-immodule.cache` | Home Manager input-method/session modules |
| `firefox-154.0` | [`home/keewai/citrus/browser.nix`](../home/keewai/citrus/browser.nix) through the pinned Home Manager adapter |
| `hyprlock-0.9.6` | Home Manager `programs.hyprlock` |
| `hypridle-0.1.8` | Home Manager `services.hypridle` and an explicit `home.packages` entry, preserving both the generated user unit and the command-line package |
| `qt5ct-1.9`, `qt6ct-0.11` | Home Manager/Stylix Qt target |
| `thunar-with-plugins-4.20.9`, `xfconf-4.20.0` | [`home/keewai/citrus/desktop.nix`](../home/keewai/citrus/desktop.nix), with Home Manager publishing the plugin-aware Thunar unit and xfconf user unit |

## Evaluated Home Manager package roots

### Citrus Home Manager roots

The first group is declared directly in the repository. The remaining groups
are generated by Home Manager or imported modules but are still part of the
evaluated `home.packages` root list.

| source module | roots |
| --- | --- |
| [`home/keewai/citrus/input-method.nix`](../home/keewai/citrus/input-method.nix) via pinned `nix-hazkey.homeModules.hazkey` | `hazkey-settings-0.2.1` |
| [`home/keewai/citrus/dynamic-island.nix`](../home/keewai/citrus/dynamic-island.nix) via pinned `dynamic-island.homeManagerModules.default` | `dynamic-island-0.1.0` |
| [`home/keewai/citrus/shell.nix`](../home/keewai/citrus/shell.nix) | `btop-1.4.7`, `duf-0.9.1`, `du-dust-1.2.5`, `fd-10.4.2`, `zsh-completions-0.36.0` |
| [`home/keewai/citrus/ipad.nix`](../home/keewai/citrus/ipad.nix) | `pymobiledevice3` (the generated `_pymobiledevice3` completion root is listed below) |
| [`home/keewai/citrus/desktop.nix`](../home/keewai/citrus/desktop.nix) | `apple-music-client-0.2.0-400b2b4`, `alac-room-auth-service-0.0.2-20260710`, `chatgpt-desktop-26.901.41123`, `brightnessctl-0.5.1`, `ddcutil-2.2.7`, `grimblast-0.1-unstable-2026-06-30`, `network-manager-applet-1.36.0`, `pavucontrol-6.2`, `yt-dlp-2026.08.19`, `gws-0.22.5`, `xarchiver-0.5.4.27`, `thunar-with-plugins-4.20.9`, `xfconf-4.20.0`, `noto-fonts-2026.08.01` |
| [`home/keewai/citrus/codex.nix`](../home/keewai/citrus/codex.nix) | `cua-driver-0.22.2`, `rtk-0.45.0` |
| [`home/keewai/citrus/browser.nix`](../home/keewai/citrus/browser.nix) | `brave-origin-1.94.117`, `pywalfox-native-2.9.0` |
| [`home/keewai/citrus/bitwarden.nix`](../home/keewai/citrus/bitwarden.nix) | `bitwarden-desktop-2026.8.0`, `pinentry-gnome3-1.3.2`, `island-bitwarden-setup` |
| [`home/keewai/common.nix`](../home/keewai/common.nix) | `git-2.55.0`, `ripgrep-15.2.0` |
| pinned nixcord module imported by [`home/keewai/citrus/desktop.nix`](../home/keewai/citrus/desktop.nix) | `legcord-1.3.0` |
| pinned `my-firefox-nix` module adapted by [`home/keewai/citrus/browser.nix`](../home/keewai/citrus/browser.nix) | `firefox-154.0` |
| Home Manager `programs.zsh` and site-function generation | `_pymobiledevice3`, `zsh-5.9.2`, `nix-zsh-completions-0.5.1-unstable-2025-12-12` |
| Home Manager `programs.zoxide`, `starship`, `rbw`, `quickshell`, `man` | `zoxide-0.10.0`, `starship-1.26.0`, `rbw-1.15.0`, `quickshell-0.3.0`, `man-db-2.13.1` |
| Home Manager `programs.kitty`, `hyprlock`, `fzf`, `eza`, `bat` | `kitty-0.48.2`, `hackgen-nf-font-2.10.0`, `hyprlock-0.9.6`, `fzf-0.74.3`, `eza-0.23.5`, `bat-0.26.1` |
| Home Manager `services.hypridle`, `services.hyprsunset`, `services.cliphist` | `hypridle-0.1.8`, `hyprsunset-0.4.0`, `cliphist-0.7.0` |
| Home Manager/Stylix Qt target | `qt5ct-1.9`, `qt6ct-0.11`, `qtstyleplugin-kvantum5-1.1.8`, `qtstyleplugin-kvantum-1.1.8` |
| Home Manager/Stylix GTK target and font target | `adw-gtk3-6.5`, `colloid-icon-theme-2026-08-10`, `colloid-cursors-2025-07-19`, `nerd-fonts-jetbrains-mono-3.5.0+2.304`, `dejavu-fonts-2.37`, `noto-fonts-cjk-sans-2.004`, `noto-fonts-color-emoji-2.051` |
| Home Manager `modules/misc/fontconfig.nix` | `dummy-fc-dir1`, `dummy-fc-dir2` |
| Home Manager `modules/misc/qt`, `gtk`, and `config/home-cursor.nix` | `index.theme`; `colloid-cursors` is a repeated root |
| Home Manager manual, input-method, and session modules | `home-configuration-reference-manpage`, `fcitx5-with-addons-5.1.21`, `gtk2-immodule.cache`, `gtk3-immodule.cache`, `hm-session-vars.sh` |
| Home Manager XDG modules | `xdg-user-dirs-0.20`, `shared-mime-info-2.4`, `dummy-xdg-mime-dirs1`, `dummy-xdg-mime-dirs2`, `everglide-web-driver.desktop`, `openmouse.desktop` |

The effective citrus Home Manager names, in evaluated order, are:

```text
legcord-1.3.0
nerd-fonts-jetbrains-mono-3.5.0+2.304
dejavu-fonts-2.37
noto-fonts-cjk-sans-2.004
noto-fonts-color-emoji-2.051
hazkey-settings-0.2.1
dynamic-island-0.1.0
btop-1.4.7
duf-0.9.1
du-dust-1.2.5
fd-10.4.2
zsh-completions-0.36.0
pymobiledevice3
hypridle-0.1.8
apple-music-client-0.2.0-400b2b4
alac-room-auth-service-0.0.2-20260710
chatgpt-desktop-26.901.41123
brightnessctl-0.5.1
ddcutil-2.2.7
grimblast-0.1-unstable-2026-06-30
network-manager-applet-1.36.0
pavucontrol-6.2
yt-dlp-2026.08.19
gws-0.22.5
xarchiver-0.5.4.27
thunar-with-plugins-4.20.9
xfconf-4.20.0
noto-fonts-2026.08.01
cua-driver-0.22.2
rtk-0.45.0
brave-origin-1.94.117
pywalfox-native-2.9.0
bitwarden-desktop-2026.8.0
pinentry-gnome3-1.3.2
island-bitwarden-setup
firefox-154.0
xdg-user-dirs-0.20
shared-mime-info-2.4
dummy-xdg-mime-dirs1
dummy-xdg-mime-dirs2
everglide-web-driver.desktop
openmouse.desktop
git-2.55.0
ripgrep-15.2.0
_pymobiledevice3
zsh-5.9.2
nix-zsh-completions-0.5.1-unstable-2025-12-12
zoxide-0.10.0
starship-1.26.0
rbw-1.15.0
quickshell-0.3.0
man-db-2.13.1
kitty-0.48.2
hackgen-nf-font-2.10.0
hyprlock-0.9.6
fzf-0.74.3
eza-0.23.5
bat-0.26.1
hyprsunset-0.4.0
cliphist-0.7.0
qt5ct-1.9
qt6ct-0.11
qtstyleplugin-kvantum5-1.1.8
qtstyleplugin-kvantum-1.1.8
adw-gtk3-6.5
colloid-icon-theme-2026-08-10
colloid-cursors-2025-07-19
noto-fonts-cjk-sans-2.004
dummy-fc-dir1
dummy-fc-dir2
home-configuration-reference-manpage
fcitx5-with-addons-5.1.21
gtk2-immodule.cache
gtk3-immodule.cache
hm-session-vars.sh
colloid-cursors-2025-07-19
index.theme
```

### Orange Home Manager roots

Orange imports only [`home/keewai/common.nix`](../home/keewai/common.nix);
the rest is generated Home Manager infrastructure:

| source module | roots |
| --- | --- |
| Home Manager XDG mime module | `shared-mime-info-2.4`, `dummy-xdg-mime-dirs1`, `dummy-xdg-mime-dirs2` |
| [`home/keewai/common.nix`](../home/keewai/common.nix) | `git-2.55.0`, `ripgrep-15.2.0` |
| Home Manager `programs.man`, fontconfig, manual, and session modules | `man-db-2.13.1`, `dummy-fc-dir1`, `dummy-fc-dir2`, `home-configuration-reference-manpage`, `hm-session-vars.sh` |

The unique evaluated orange Home Manager list is:

```text
shared-mime-info-2.4
dummy-xdg-mime-dirs1
dummy-xdg-mime-dirs2
git-2.55.0
ripgrep-15.2.0
man-db-2.13.1
dummy-fc-dir1
dummy-fc-dir2
home-configuration-reference-manpage
hm-session-vars.sh
```

## System fonts and build-only/runtime scopes

### Fonts

The baseline citrus `fonts.packages` definitions were:

| source | evaluated roots |
| --- | --- |
| pinned Stylix `modules/font-packages/nixos.nix` | `nerd-fonts-jetbrains-mono-3.5.0+2.304`, `dejavu-fonts-2.37`, `noto-fonts-cjk-sans-2.004`, `noto-fonts-color-emoji-2.051` |
| [`hosts/citrus/default.nix`](../hosts/citrus/default.nix) | `noto-fonts-2026.08.01` |
| locked nixpkgs `nixos/modules/config/fonts/packages.nix` defaults | `dejavu-fonts-2.37`, `freefont-ttf-20120503`, `gyre-fonts-2.501`, `liberation-fonts-2.1.5`, `unifont-17.0.05`, `noto-fonts-cjk-sans-2.004`, `noto-fonts-cjk-serif-2.003`, `noto-fonts-color-emoji-2.051` |

The accompanying configuration keeps the locked nixpkgs default set in NixOS for global
fallback and moves the explicit host `noto-fonts` root and Stylix-selected
roots into Home Manager. Some names therefore appear in both scopes: for
example, DejaVu, Noto CJK Sans, and Noto Color Emoji are both part of the
global defaults and selected user theme inputs. The Home Manager [fontconfig
target](https://home-manager.dev/manual/unstable/options/home-manager/fonts.html)
makes the user-scoped roots discoverable in the user's profile.

The baseline `config.programs.steam.fontPackages` value equaled the baseline
`config.fonts.packages` list. The accompanying configuration assigns Steam an explicit list
of `config.stylix.fonts.packages ++ [ pkgs.noto-fonts ] ++ config.fonts.packages`;
the evaluated store-path vector is identical to the baseline vector. This
preserves the NixOS [Steam module](https://wiki.nixos.org/wiki/Steam) FHS
environment and Japanese rendering while moving personal font roots to Home
Manager. The current HM-only Qt roots are independent:
NixOS `config.qt.enable = false`, while the HM Stylix Qt target evaluates
`qt5ct`, `qt6ct`, and both Kvantum style plugins into the user profile.

### Explicit service and runtime inputs

These are intentionally excluded from the interactive root counts above.

| consumer | explicit inputs and scope |
| --- | --- |
| [`hosts/citrus/fingerprint.nix`](../hosts/citrus/fingerprint.nix) | Custom `fprintd` wraps a pinned `libfprint-CS9711`; `opencv4` is a build input and `doctest` is a native build/test input. The fprintd daemon remains system-owned. |
| [`hosts/citrus/codex.nix`](../hosts/citrus/codex.nix) | Pinned Ponytail source is checked with `nodejs`; generated hook wrappers use `nodejs` and `coreutils`. The CUA MCP wrapper uses `systemd`; user activation uses `yq-go`; Serena's declared extra packages are `nixd` and `nixfmt`. These are helper/runtime or build inputs, not extra personal roots. |
| [`home/keewai/citrus/ipad.nix`](../home/keewai/citrus/ipad.nix) | The wrapper uses `stdenv.cc`/its compiler library, `zlib`, `libusb1`, `uv`, and `python313`, then runs the pinned `pymobiledevice3==11.4.2` tool. The compiler is retained because lzfse may compile on first install. |
| [`home/keewai/citrus/bitwarden.nix`](../home/keewai/citrus/bitwarden.nix) | The setup helper runtime is `kitty`, `rbw`, and `jq`; the direct user roots are Bitwarden Desktop and `pinentry-gnome3`. |
| [`hosts/orange/services/health-monitor.nix`](../hosts/orange/services/health-monitor.nix) | Service runtime inputs: `coreutils`, `curl`, `findutils`, `gawk`, `gnugrep`, `gnused`, `iproute2`, `jq`, `netcat-openbsd`, `smartmontools`, `systemd`, `tailscale`, and `util-linux`. Its check derivation uses `coreutils`, `findutils`, and `gnugrep` as native build inputs. |
| [`hosts/orange/services/immich.nix`](../hosts/orange/services/immich.nix) | `postgresql_17` is the pinned database/service package; the one-shot import helper uses `coreutils`, `findutils`, `gzip`, and `util-linux`. `intel-media-driver` and `vpl-gpu-rt` are hardware acceleration runtime packages. |
| [`hosts/orange/services/vaultwarden.nix`](../hosts/orange/services/vaultwarden.nix) | The one-shot import helper uses `coreutils`, `findutils`, `rsync`, and `sqlite`. Vaultwarden itself remains provided by its NixOS service module. |
| [`hosts/orange/services/maintenance.nix`](../hosts/orange/services/maintenance.nix) | Local backup runtime: `coreutils`, `findutils`, `gnutar`, `systemd`, and `zstd`; SMART helpers use `smartmontools`; store verification uses the configured Nix package. |
| [`hosts/orange/services/storage.nix`](../hosts/orange/services/storage.nix) and [`hosts/orange/default.nix`](../hosts/orange/default.nix) | Mount preparation uses `coreutils`; the NetworkManager dispatcher uses `ethtool`. Samba remains a system service. |
| [`hosts/orange/services/minecraft.nix`](../hosts/orange/services/minecraft.nix) | The system service runs `jdk25_headless`. Fabric launcher, the Mojang server jar, and the pinned Lithium, Krypton, and ScalableLux jars are fetched artifacts, not interactive package roots. |
| [`hosts/orange/services/web.nix`](../hosts/orange/services/web.nix) | The Tailscale Serve systemd unit invokes the system `tailscale` binary; nginx and the application backends remain service-owned. |
| [`hosts/citrus/browser.nix`](../hosts/citrus/browser.nix) | The WebHID udev rules are a generated udev data package. They are hardware access integration, not a user application root. |
| [`hosts/citrus/default.nix`](../hosts/citrus/default.nix) | greetd invokes `tuigreet` and `uwsm`; Hyprland, the patched portal, NVIDIA driver, and CachyOS kernel are session/driver integration. |

## Migration decisions

- **Keep personal applications and user CLI tools in Home Manager.** The
  direct citrus roots are now declared under `home/keewai/common.nix` and
  `home/keewai/citrus/`: Apple Music/auth, ChatGPT Desktop, Bitwarden
  Desktop/pinentry, brightnessctl, ddcutil, grimblast, NetworkManager applet,
  pavucontrol, yt-dlp, gws, xarchiver, the Thunar client, xfconf, Brave
  Origin, Pywalfox, pymobiledevice3, CUA/RTK, shell tools, git, and ripgrep.
  This preserves user availability while keeping host modules focused on
  machine integration.

- **Keep system-owned daemon and hardware integration.** NetworkManager,
  Blueman, usbmuxd and its Apple udev rules, PipeWire/WirePlumber, GVFS,
  Tumbler, fprintd/PAM, Steam's graphics/audio setup, Hyprland's session,
  portals, setuid/capability wrappers, NVIDIA, and system fonts remain
  NixOS-owned.

- **Hyprlock and hypridle are now Home Manager-owned.** The NixOS dynamic
  island module keeps the upstream PAM service but forces
  `programs.hyprlock.enable = false`; Home Manager owns the user package and
  `services.hypridle` unit. This removes the duplicate NixOS user-service
  roots while retaining authentication and user-session behavior.

- **Thunar and xfconf use Home Manager plus user-unit publication.** The
  explicit Home Manager package roots are paired with
  a link to Thunar’s plugin-aware `lib/systemd/user/thunar.service` and
  `systemd.user.packages` for xfconf. Directory MIME association points at
  `thunar.desktop`. This is the user-scoped replacement for the NixOS
  Thunar module's package/unit publication; the package ownership check
  confirms the expected Thunar/xfconf D-Bus service and user-unit paths,
  including Thunar’s wrapped `ExecStart`. The package’s `share/systemd/user`
  unit starts the unwrapped binary and must not be used.

- **Firefox is user-scoped with feature parity.** The [Home Manager Firefox
  options](https://home-manager.dev/manual/unstable/options/home-manager/programs/firefox.html)
  adapter
  reuses the pinned Sine/Natsumi package settings, preserves the autoconfig
  file, language packs, locked policies, and Pywalfox native host manifest.
  The manifest is installed under the user Firefox native-messaging directory;
  the pinned upstream input is selected from `main`.

- **Hazkey and Fcitx5 are user-scoped.** The pinned Hazkey Home Manager module
  provides the settings package and user service; the Home Manager input-method
  module keeps the writable user profile and XDG autostart behavior.

- **Qt is user-scoped.** NixOS `qt.enable` is false; the Home Manager
  Stylix target owns qt5ct, qt6ct, Kvantum, and their generated settings.

- **Fonts are split by scope.** Keep the NixOS default font package set
  system-scoped for global consumers. Move the explicit `noto-fonts` and
  Stylix-selected font roots to Home Manager, and set an explicit
  `programs.steam.fontPackages` list containing those selected fonts plus the
  remaining `config.fonts.packages` defaults. This preserves the baseline
  Steam font vector while allowing personal font roots to follow the user's
  profile.

- **Do not migrate private service runtimes into interactive profiles.** The
  service runtime/build inputs above belong to their consumers and should
  remain in the service or derivation definitions.

## Pinned source references

The root flake input and lock data are the reproducibility boundary:

| input | locked reference |
| --- | --- |
| nixpkgs | [`github:NixOS/nixpkgs`](https://github.com/NixOS/nixpkgs/tree/56c02bc00adcf003215cc4bd996d6efaf4cff188), rev `56c02bc00adcf003215cc4bd996d6efaf4cff188` (`nixos-unstable`) |
| Home Manager | [`github:nix-community/home-manager`](https://github.com/nix-community/home-manager/tree/99c9ec63390f1d8c14d95d9e8b17cc29cfbd4e11), rev `99c9ec63390f1d8c14d95d9e8b17cc29cfbd4e11` (`master`) |
| Stylix | [`github:nix-community/stylix`](https://github.com/nix-community/stylix/tree/5e3809851f486e7fc7e84b40f174c74b60ecc784), rev `5e3809851f486e7fc7e84b40f174c74b60ecc784` |
| dynamic-island | local [`/home/keewai/dynamic-island`](/home/keewai/dynamic-island), ref `main`, rev `1cb9cbe0f208b8acd25346faf9c384d5e9fb6159` |
| my-firefox-nix | [`github:keewai704/my-firefox-nix`](https://github.com/keewai704/my-firefox-nix/tree/ea344d520247a1b2e97931b13248b3f846d2177f), ref `main`, rev `ea344d520247a1b2e97931b13248b3f846d2177f` |
| nix-hazkey | [`github:aster-void/nix-hazkey`](https://github.com/aster-void/nix-hazkey/tree/24cb2926666836988e78ceebeb67ad6c5a387ac3), rev `24cb2926666836988e78ceebeb67ad6c5a387ac3` |
| nixcord | [`github:4evy/nixcord`](https://github.com/4evy/nixcord/tree/cbedffd31cad83b2db80ea30f790cffefc4777f), rev `cbedffd31cad83b2db80ea30f790cffefc4777f` |
| mcp-servers-nix | [`github:natsukium/mcp-servers-nix`](https://github.com/natsukium/mcp-servers-nix/tree/dbb2006631de0bfb1e1a976ee83ce3e84704480e), rev `dbb2006631de0bfb1e1a976ee83ce3e84704480e` |
| apple-music-client | [`github:keewai704/apple-music-client`](https://github.com/keewai704/apple-music-client/tree/400b2b43b1c2a47bc5094a7129afe287ea210152), ref `main`, rev `400b2b43b1c2a47bc5094a7129afe287ea210152` |
| Millennium | [`github:SteamClientHomebrew/Millennium`](https://github.com/SteamClientHomebrew/Millennium/tree/d0f88ac144265e5dad207c13c5b4fb0aaaac5134/packages/nix), rev `d0f88ac144265e5dad207c13c5b4fb0aaaac5134`, dir `packages/nix` |

The repository-local package sources are
[`pkgs/apple-music-client`](../pkgs/apple-music-client),
[`pkgs/chatgpt-desktop`](../pkgs/chatgpt-desktop), and
[`pkgs/cua-driver`](../pkgs/cua-driver). GitHub sources owned by
`keewai704` are explicitly pinned to `main` in [`flake.nix`](../flake.nix)
and [`flake.lock`](../flake.lock).

## Known boundaries

This document inventories evaluated roots and explicitly declared service
inputs. It does not expand every transitive closure dependency of each
derivation, nor does it treat fetched fonts, browser language packs, Minecraft
jars, udev data, generated cache files, or service module internals as
interactive package ownership. Those scopes remain attached to their consumer.
