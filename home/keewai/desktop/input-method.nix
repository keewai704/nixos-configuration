{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  profileDefaults = pkgs.writeTextDir "fcitx5/profile" (
    lib.generators.toINI { } {
      "Groups/0" = {
        Name = "Default";
        "Default Layout" = "us";
        DefaultIM = "hazkey";
      };
      "Groups/0/Items/0" = {
        Name = "keyboard-us";
        Layout = "";
      };
      "Groups/0/Items/1" = {
        Name = "hazkey";
        Layout = "";
      };
      GroupOrder."0" = "Default";
    }
  );
in
{
  imports = [ inputs.nix-hazkey.homeModules.hazkey ];
  services.hazkey.enable = true;
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";

    fcitx5 = {
      waylandFrontend = true;
      systemd.enable = false;
    };
  };

  xdg = {
    systemDirs.config = [
      "${profileDefaults}"
      "/etc/xdg"
    ];

    configFile = {
      "autostart/org.fcitx.Fcitx5.desktop".source =
        "${config.i18n.inputMethod.package}/share/applications/org.fcitx.Fcitx5.desktop";

      fcitx5.recursive = true;
    };
  };
  stylix.targets.fcitx5.enable = true;
}
