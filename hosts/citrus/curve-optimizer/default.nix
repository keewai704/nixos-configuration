{ lib, pkgs, ... }:
let
  margins = [
    (-29)
    (-19)
    (-29)
    (-19)
    (-24)
    (-14)
    (-34)
    (-44)
  ];

  apply = pkgs.writers.writePython3Bin "curve-optimizer-apply" { } (builtins.readFile ./apply.py);
in
{
  hardware.cpu.amd.ryzen-smu.enable = true;

  systemd.settings.Manager.RuntimeWatchdogSec = "30s";

  systemd.services.curve-optimizer = {
    description = "Apply per-core Curve Optimizer margins";
    wantedBy = [
      "multi-user.target"
      "post-resume.target"
    ];
    after = [
      "systemd-modules-load.service"
      "post-resume.target"
    ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${lib.getExe apply} ${lib.concatMapStringsSep " " toString margins}";
    };
  };
}
