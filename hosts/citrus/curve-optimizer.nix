{ pkgs, ... }:
{
  hardware.cpu.amd.ryzen-smu.enable = true;

  systemd.settings.Manager.RuntimeWatchdogSec = "30s";

  systemd.services.co-tune-resume = {
    description = "Resume interrupted Curve Optimizer tuning";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-modules-load.service" ];
    unitConfig.ConditionPathExists = "/var/lib/co-tune/active";
    path = [
      pkgs.util-linux
      pkgs.systemd
    ];
    serviceConfig = {
      Type = "exec";
      TimeoutStartSec = "5min";
      WorkingDirectory = "/var/lib/co-tune";
      ExecStartPre = "${pkgs.coreutils}/bin/sleep 120";
      ExecStart = "${pkgs.python3}/bin/python3 -I /var/lib/co-tune/tune.py";
    };
  };
}
