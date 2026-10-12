{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
{
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";

    fcitx5 = {
      addons = [
        (pkgs.callPackage ../../../pkgs/meltype {
          release = inputs.meltype-release;
          tags = inputs.meltype-tags;
        })
      ];
      waylandFrontend = true;
      systemd.enable = false;
      settings.globalOptions."Hotkey/TriggerKeys" = {
        "0" = "Henkan_Mode";
        "1" = "Zenkaku_Hankaku";
        "2" = "Hangul";
      };
      settings.inputMethod = {
        "Groups/0" = {
          Name = "Default";
          "Default Layout" = "us";
          DefaultIM = "meltype";
        };
        "Groups/0/Items/0" = {
          Name = "keyboard-us";
          Layout = "";
        };
        "Groups/0/Items/1" = {
          Name = "meltype";
          Layout = "";
        };
        GroupOrder."0" = "Default";
      };
      themes.stylix.theme = {
        "InputPanel/Background/Margin" = lib.mapAttrs (_: lib.mkForce) {
          Left = 14;
          Right = 14;
          Top = 14;
          Bottom = 14;
        };
        "InputPanel/Highlight/Margin" = lib.mapAttrs (_: lib.mkForce) {
          Left = 14;
          Right = 14;
        };
      };
    };
  };

  xdg.configFile = {
    "autostart/org.fcitx.Fcitx5.desktop".source =
      "${config.i18n.inputMethod.package}/share/applications/org.fcitx.Fcitx5.desktop";

    fcitx5.recursive = true;
  };
  stylix.targets.fcitx5.enable = true;
}
