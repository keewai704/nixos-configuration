{ lib, pkgs, ... }:
let
  target = "gpu-workloads.target";
  systemctl = lib.getExe' pkgs.systemd "systemctl";
in
{
  systemd.targets.gpu-workloads = {
    description = "Services that keep GPU memory allocated";
    wantedBy = [ "multi-user.target" ];
  };

  systemd.services =
    lib.genAttrs
      [
        "immich-machine-learning"
        "plamo-server"
        "stt-server"
      ]
      (_: {
        partOf = [ target ];
        wantedBy = [ target ];
      });

  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (action.id == "org.freedesktop.systemd1.manage-units" &&
          action.lookup("unit") == "${target}" &&
          (action.lookup("verb") == "start" || action.lookup("verb") == "stop") &&
          subject.user == "keewai") {
        return polkit.Result.YES;
      }
    });
  '';

  programs.gamemode.settings.custom = {
    start = "${systemctl} stop ${target}";
    end = "${systemctl} start --no-block ${target}";
    script_timeout = 30;
  };
}
