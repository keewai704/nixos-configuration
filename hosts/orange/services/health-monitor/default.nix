{
  config,
  fillTemplate,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.orange.healthMonitor;
  inherit (import ../../settings.nix)
    immichBackupRoot
    localBackupRoot
    minecraftPort
    nginxPort
    smartDevices
    storageRoot
    tailnetHostname
    tailnetOrigin
    vaultwardenBackupRoot
    ;

  monitoredUnits = lib.unique cfg.units;
  monitoredUserUnits = lib.unique cfg.userUnits;

  loopbackBackendPorts = lib.unique cfg.loopbackPorts;
  loopbackBackendPortPattern = lib.concatStringsSep "|" (map toString loopbackBackendPorts);

  scriptReplacements = {
    "@monitoredUnits@" = lib.escapeShellArgs monitoredUnits;
    "@monitoredUserUnits@" = lib.escapeShellArgs monitoredUserUnits;
    "@storageRootArg@" = lib.escapeShellArg storageRoot;
    "@storageRoot@" = storageRoot;
    "@smartDevices@" = lib.escapeShellArgs smartDevices;
    "@tailnetOrigin@" = tailnetOrigin;
    "@nginxPort@" = toString nginxPort;
    "@tailnetHostname@" = tailnetHostname;
    "@minecraftPort@" = toString minecraftPort;
    "@loopbackBackendPortPattern@" = loopbackBackendPortPattern;
    "@immichBackupRoot@" = lib.escapeShellArg immichBackupRoot;
    "@vaultwardenBackupRoot@" = lib.escapeShellArg vaultwardenBackupRoot;
    "@minecraftBackupRoot@" = lib.escapeShellArg "${localBackupRoot}/minecraft";
    "@versionedVaultwardenBackupRoot@" = lib.escapeShellArg "${localBackupRoot}/vaultwarden";
  };

  healthMonitor = pkgs.writeShellApplication {
    name = "orange-health-monitor";
    runtimeInputs = with pkgs; [
      coreutils
      curl
      findutils
      gawk
      gnugrep
      gnused
      iproute2
      jq
      netcat-openbsd
      smartmontools
      systemd
      tailscale
      util-linux
    ];
    text = fillTemplate ./health-monitor.sh scriptReplacements;
  };
in
{
  options.orange.healthMonitor = {
    units = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "System units checked for an active state, including service or socket suffixes.";
    };
    userUnits = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "keewai user units checked for an active state, including unit suffixes.";
    };
    loopbackPorts = lib.mkOption {
      type = lib.types.listOf lib.types.port;
      default = [ ];
      description = "Backend TCP ports that must only listen on loopback addresses.";
    };
  };

  config = {
    orange.healthMonitor.units = [
      "NetworkManager.service"
      "tailscaled.service"
      "sshd.service"
    ];

    age.secrets.discord-webhook = {
      file = ../../../../secrets/discord-webhook.age;
      mode = "0400";
      owner = "root";
      group = "root";
    };

    systemd = {
      services = {
        orange-health-monitor = {
          description = "Monitor orange and notify Discord only on new failures";
          wants = [ "network-online.target" ];
          after = [
            "network-online.target"
          ]
          ++ monitoredUnits;
          serviceConfig = {
            Type = "oneshot";
            ExecStart = lib.getExe healthMonitor;
            LoadCredential = "discord-webhook:${config.age.secrets.discord-webhook.path}";
            StateDirectory = "orange-health-monitor";
            StateDirectoryMode = "0700";
            RuntimeDirectory = "orange-health-monitor";
            RuntimeDirectoryMode = "0700";
            UMask = "0077";
            NoNewPrivileges = true;
            PrivateTmp = true;
            ProtectSystem = "full";
            ProtectHome = "tmpfs";
            BindReadOnlyPaths = [ "/run/user" ];
            ProtectClock = true;
            ProtectControlGroups = true;
            ProtectKernelLogs = false;
            ProtectKernelModules = true;
            ProtectKernelTunables = true;
            RestrictAddressFamilies = [
              "AF_UNIX"
              "AF_INET"
              "AF_INET6"
            ];
          };
        };
      };

      timers = {
        orange-health-monitor = {
          description = "Check orange health every 15 minutes";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnBootSec = "10min";
            OnUnitActiveSec = "15min";
            AccuracySec = "1min";
          };
        };
      };
    };
  };
}
