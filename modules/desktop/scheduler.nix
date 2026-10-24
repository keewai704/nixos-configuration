{
  config,
  lib,
  pkgs,
  ...
}:
{
  assertions = [
    {
      assertion = lib.versionAtLeast config.boot.kernelPackages.kernel.version "6.12";
      message = "Automatic sched_ext switching requires Linux 6.12 or newer.";
    }
  ];

  systemd.services.scx-auto = {
    description = "Automatically switch between EEVDF and LAVD based on CPU utilization";
    wantedBy = [ "multi-user.target" ];
    after = [
      "scx.service"
      "scx_loader.service"
    ];
    conflicts = [
      "scx.service"
      "scx_loader.service"
    ];
    path = [ pkgs.scx.rustscheds ];
    unitConfig.ConditionPathIsDirectory = "/sys/kernel/sched_ext";
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.scx-loader}/bin/scx_loader --auto";
      Restart = "on-failure";
      RestartSec = "5s";
      KillMode = "control-group";
    };
  };
}
