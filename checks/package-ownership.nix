{
  lib,
  pkgs,
  citrus,
  orange,
}:
let
  home = citrus.home-manager.users.keewai;
  names = packages: map lib.getName packages;
  onlyAtHome =
    system: packages:
    lib.all (
      name:
      builtins.elem name (names system.home-manager.users.keewai.home.packages)
      && !(builtins.elem name (names system.environment.systemPackages))
    ) packages;
in
assert onlyAtHome orange [
  "git"
  "ripgrep"
];
assert onlyAtHome citrus [
  "git"
  "ripgrep"
  "apple-music-client"
  "alac-room-auth-service"
  "chatgpt-desktop"
  "bitwarden-desktop"
  "pinentry-gnome3"
  "island-bitwarden-setup"
  "brave-origin"
  "pywalfox-native"
  "firefox"
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
];
assert citrus.security.pam.services ? hyprlock;
assert !citrus.services.hypridle.enable;
assert home.services.hypridle.enable;
assert !home.i18n.inputMethod.fcitx5.systemd.enable;
assert home.services.hazkey.enable;
assert citrus.services.usbmuxd.enable && citrus.hardware.i2c.enable;
assert home.programs.firefox.languagePacks == [ "ja" ];
assert home.programs.firefox.policies.Preferences."intl.locale.requested".Value == "ja";
assert home.programs.firefox.policies.Preferences."sine.auto-updates".Status == "locked";
assert builtins.elem "noto-fonts" (names home.home.packages);
assert !(builtins.elem "noto-fonts" (names citrus.fonts.packages));
assert lib.all (
  font: builtins.elem (toString font) (map toString citrus.programs.steam.fontPackages)
) (citrus.stylix.fonts.packages ++ [ pkgs.noto-fonts ]);
pkgs.runCommand "package-ownership" { } ''
  # Check actual launch integration, not just the presence of package names.
  test -x ${home.home.path}/bin/chatgpt
  test -f ${home.home.path}/share/applications/chatgpt.desktop
  test -f ${home.home.path}/share/dbus-1/services/org.xfce.Thunar.service
  test -f ${home.home.path}/share/dbus-1/services/org.xfce.Xfconf.service
  thunar_command=$(${pkgs.gnused}/bin/sed -n 's/^ExecStart=\(.*\) --daemon$/\1/p' \
    ${home.xdg.configFile."systemd/user/thunar.service".source})
  test "$(readlink -f "$thunar_command")" = "$(readlink -f ${home.home.path}/bin/Thunar)"
  test -f ${home.xdg.dataFile."systemd/user".source}/xfconfd.service
  test -f ${home.home.file.".mozilla/native-messaging-hosts".source}/pywalfox.json
  ${pkgs.gnugrep}/bin/grep -q 'chrome://userscripts/content/sine.sys.mjs' \
    ${home.programs.firefox.finalPackage}/lib/firefox/mozilla.cfg
  test ! -e ${home.xdg.configFile.fcitx5.source}/profile
  test -f ${home.xdg.configFile."autostart/org.fcitx.Fcitx5.desktop".source}
  touch "$out"
''
