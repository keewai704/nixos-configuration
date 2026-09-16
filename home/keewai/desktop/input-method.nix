{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
{
  imports = [ inputs.nix-hazkey.homeModules.hazkey ];
  services.hazkey.enable = true;
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";

    fcitx5 = {
      addons = [
        (pkgs.writeShellScriptBin "hazkey-server" ''
          case "$*" in
            "") action=start ;;
            -r|--replace) action=restart ;;
            *) exit 64 ;;
          esac
          exec ${lib.getExe' pkgs.systemd "systemctl"} --user "$action" hazkey-server.service
        '')
      ];
      waylandFrontend = true;
      systemd.enable = false;
      settings.globalOptions."Hotkey/TriggerKeys" = {
        "0" = "Control+grave";
        "1" = "Zenkaku_Hankaku";
        "2" = "Hangul";
      };
      settings.inputMethod = {
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
