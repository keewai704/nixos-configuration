{ lib, pkgs, ... }:
{
  fonts.packages = [ pkgs.inter ];

  home-manager.users.keewai = {
    programs.quickshell = {
      enable = true;
      activeConfig = "dynamic-island";
      configs.dynamic-island = ./dynamic-island;
      systemd.enable = true;
    };
    # Noctalia continues to provide wallpaper, locking, Polkit and hardware panels.
    programs.noctalia.settings = {
      bar.default.enabled = false;
      notification.enable_daemon = false;
      osd.enabled = false;
    };
    systemd.user.services.quickshell = {
      Unit = {
        After = [ "noctalia.service" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        Environment = [ "ISLAND_NOCTALIA=${lib.getExe pkgs.noctalia}" ];
        RestartSec = 2;
      };
    };
    home.packages = [
      (pkgs.writeShellApplication {
        name = "islandctl";
        runtimeInputs = [ pkgs.quickshell ];
        text = ''
          exec qs -c dynamic-island ipc call island "''${@:-toggle}"
        '';
      })
    ];
  };
}
