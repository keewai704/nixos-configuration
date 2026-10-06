{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (import ../settings.nix)
    immichBackupRoot
    immichPort
    localBackupRoot
    minecraftPort
    nginxPort
    smartDevices
    storageRoot
    tailnetHostname
    tailnetOrigin
    vaultwardenBackupRoot
    vaultwardenPort
    ;

  monitoredServices = [
    "NetworkManager"
    "tailscaled"
    "sshd"
    "samba-smbd"
    "immich-server"
    "postgresql"
    "redis-immich"
    "vaultwarden"
    "nginx"
    "minecraft"
    "tailscale-serve-nginx"
  ];
  monitoredServiceUnits = map (service: "${service}.service") monitoredServices;

  loopbackBackendPorts = [
    immichPort
    nginxPort
    vaultwardenPort
  ];
  loopbackBackendPortPattern = lib.concatStringsSep "|" (map toString loopbackBackendPorts);

  scriptReplacements = {
    "@monitoredServices@" = lib.escapeShellArgs monitoredServices;
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
    text = lib.replaceStrings (lib.attrNames scriptReplacements) (lib.attrValues scriptReplacements) (
      builtins.readFile ./health-monitor.sh
    );
  };
in
{
  age.secrets.discord-webhook = {
    file = ../../../secrets/discord-webhook.age;
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
        ++ monitoredServiceUnits;
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
          ProtectHome = true;
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
}
