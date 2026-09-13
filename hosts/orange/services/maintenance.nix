{
  config,
  lib,
  ...
}:
{
  services.fstrim.interval = "Mon *-*-* 06:50:00";

  nix = {
    gc.dates = lib.mkForce "Mon *-*-* 07:00:00";
    optimise.dates = lib.mkForce [ "*-*-* 06:40:00" ];
  };

  systemd = {
    suppressedSystemUnits = [ "systemd-tmpfiles-clean.timer" ];

    services = {
      orange-nix-store-verify = {
        description = "Verify Nix Store contents monthly";
        startAt = "*-*-01 08:00:00";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${config.nix.package}/bin/nix-store --verify --check-contents";
          Nice = 10;
          IOSchedulingClass = "idle";
        };
      };
    };

    timers = {
      logrotate = {
        timerConfig = {
          OnCalendar = lib.mkForce "*-*-* 06:20:00";
          Persistent = false;
        };
      };

      orange-tmpfiles-clean = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "*-*-* 06:30:00";
          Unit = "systemd-tmpfiles-clean.service";
        };
      };

      nix-gc.timerConfig.Persistent = lib.mkForce false;
      nix-optimise.timerConfig = {
        Persistent = lib.mkForce false;
        RandomizedDelaySec = lib.mkForce 0;
      };
      fstrim.timerConfig = {
        Persistent = lib.mkForce false;
        RandomizedDelaySec = lib.mkForce 0;
      };
    };
  };
}
