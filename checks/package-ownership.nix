{
  lib,
  pkgs,
  citrus,
  orange,
}:
let
  home = citrus.home-manager.users.keewai;
  orangeHome = orange.home-manager.users.keewai;
  names = packages: map lib.getName packages;
  onlyAtHome =
    system: packages:
    lib.all (
      name:
      builtins.elem name (names system.home-manager.users.keewai.home.packages)
      && !(builtins.elem name (names system.environment.systemPackages))
    ) packages;
in
assert lib.all
  (
    system:
    onlyAtHome system [
      "git"
      "ripgrep"
      "apple-music-client"
      "alac-room-auth-service"
      "chatgpt-desktop"
      "codex"
      "bitwarden-desktop"
      "pinentry-gnome3"
      "island-bitwarden-setup"
      "brave-origin"
      "brightnessctl"
      "ddcutil"
      "grimblast"
      "network-manager-applet"
      "pavucontrol"
      "xarchiver"
      "gws"
      "pymobiledevice3"
      "thunar-with-plugins"
      "xfconf"
      "hazkey-settings"
      "hyprlock"
      "hypridle"
      "qt5ct"
      "qt6ct"
    ]
  )
  [
    citrus
    orange
  ];
assert orangeHome.programs.zsh.enable && orangeHome.programs.starship.enable;
assert orangeHome.programs.mcp.servers == home.programs.mcp.servers;
assert orangeHome.programs.dynamic-island.theme == home.programs.dynamic-island.theme;
assert orangeHome.programs.codex.package == home.programs.codex.package;
assert orange.users.users.keewai.linger;
assert orange.security.pam.services ? hyprlock;
assert orange.programs.dconf.enable;
assert !orange.programs.hyprland.enable && !orange.services.greetd.enable;
# Sharing desktop settings must not start graphical services on the headless server.
assert lib.all (
  name:
  !(builtins.elem "default.target" (orangeHome.systemd.user.services.${name}.Install.WantedBy or [ ]))
) (lib.remove "codex-remote" (builtins.attrNames orangeHome.systemd.user.services));
assert citrus.security.pam.services ? hyprlock;
assert !(home.home.file.".codex/config.toml".enable or false);
assert !(home.home.file.".codex/AGENTS.md".enable or false);
assert citrus.services.fprintd.enable && home.programs.hyprlock.settings.auth.fingerprint.enabled;
assert !citrus.security.pam.services.hyprlock.fprintAuth;
assert citrus.security.pam.services.hyprlock.rules.auth.unix.enable;
assert !citrus.services.hypridle.enable;
assert home.services.hypridle.enable;
assert !home.i18n.inputMethod.fcitx5.systemd.enable;
assert home.services.hazkey.enable;
assert citrus.services.usbmuxd.enable && citrus.hardware.i2c.enable;
assert !home.programs.firefox.enable;
assert lib.all
  (name: !(builtins.elem name (names (home.home.packages ++ citrus.environment.systemPackages))))
  [
    "firefox"
    "pywalfox-native"
    "brave"
    "chromium"
  ];
assert lib.all (mime: home.xdg.mimeApps.defaultApplications.${mime} == [ "brave-origin.desktop" ]) [
  "application/xhtml+xml"
  "text/html"
  "x-scheme-handler/about"
  "x-scheme-handler/http"
  "x-scheme-handler/https"
  "x-scheme-handler/unknown"
];
assert builtins.elem "noto-fonts" (names home.home.packages);
assert !(builtins.elem "noto-fonts" (names citrus.fonts.packages));
assert lib.all (
  font: builtins.elem (toString font) (map toString citrus.programs.steam.fontPackages)
) (citrus.stylix.fonts.packages ++ [ pkgs.noto-fonts ]);
pkgs.runCommand "package-ownership" { } ''
  # Check actual launch integration, not just the presence of package names.
  test -x ${home.home.path}/bin/chatgpt
  test -x ${home.home.path}/bin/codex
  test -x ${home.home.path}/bin/codex-code-mode-host
  test -x ${home.home.file.".local/bin/codex".source}
  ${home.home.path}/bin/codex --version
  test -f ${home.home.path}/share/applications/chatgpt.desktop
  test -f ${home.home.path}/share/dbus-1/services/org.xfce.Thunar.service
  test -f ${home.home.path}/share/dbus-1/services/org.xfce.Xfconf.service
  thunar_command=$(${pkgs.gnused}/bin/sed -n 's/^ExecStart=\(.*\) --daemon$/\1/p' \
    ${home.xdg.configFile."systemd/user/thunar.service".source})
  test "$(readlink -f "$thunar_command")" = "$(readlink -f ${home.home.path}/bin/Thunar)"
  test -f ${home.xdg.dataFile."systemd/user".source}/xfconfd.service
  test -x ${home.home.path}/bin/brave-origin
  test -f ${home.home.path}/share/applications/brave-origin.desktop
  test ! -e ${home.home.path}/bin/firefox
  test ! -e ${home.home.path}/bin/pywalfox
  test ! -e ${home.xdg.configFile.fcitx5.source}/profile
  test -f ${home.xdg.configFile."autostart/org.fcitx.Fcitx5.desktop".source}
  touch "$out"
''
