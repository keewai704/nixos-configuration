{
  fillTemplate,
  lib,
  pkgs,
  ...
}:

let
  inherit (import ../../settings.nix)
    storageMountUnit
    storageRoot
    tailnetHostname
    tailnetOrigin
    vaultwardenBackupRoot
    vaultwardenPort
    ;
  mkProxyLocation = import ../web/proxy.nix;
  legacyVaultwardenRoot = "${storageRoot}/server/vaultwarden";
  storagePreparationDependencies = [
    "media-storage-prepare.service"
    storageMountUnit
  ];
  vaultwardenDependencies = [
    storageMountUnit
    "vaultwarden-import-existing.service"
  ];
  backupDependencies = storagePreparationDependencies ++ [ "vaultwarden-import-existing.service" ];

  scriptReplacements = {
    "@legacyVaultwardenRoot@" = lib.escapeShellArg legacyVaultwardenRoot;
    "@legacyDatabase@" = lib.escapeShellArg "${legacyVaultwardenRoot}/db.sqlite3";
  };

  importVaultwardenData = pkgs.writeShellApplication {
    name = "import-existing-vaultwarden-data";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.diffutils
      pkgs.findutils
      pkgs.rsync
      pkgs.sqlite
    ];
    text = fillTemplate ./import-vaultwarden-data.sh scriptReplacements;
  };
in
{
  orange.healthMonitor = {
    units = [ "vaultwarden.service" ];
    loopbackPorts = [ vaultwardenPort ];
  };

  services.vaultwarden = {
    enable = true;
    dbBackend = "sqlite";
    backupDir = vaultwardenBackupRoot;
    config = {
      DOMAIN = "${tailnetOrigin}/vault";
      EXPERIMENTAL_CLIENT_FEATURE_FLAGS = "cxp-import-mobile";
      ROCKET_ADDRESS = "127.0.0.1";
      ROCKET_PORT = vaultwardenPort;
      SIGNUPS_ALLOWED = false;
    };
  };

  services.nginx.virtualHosts.${tailnetHostname}.locations = {
    "= /vault".return = "308 ${tailnetOrigin}/vault/";
    "^~ /vault/" = mkProxyLocation vaultwardenPort "";
  };

  systemd = {
    tmpfiles = {
      rules = [ "d /var/lib/vaultwarden 0700 vaultwarden vaultwarden -" ];
      settings."10-vaultwarden" = lib.mkForce { };
    };

    services = {
      vaultwarden-import-existing = {
        description = "Import the existing Vaultwarden state once";
        requires = storagePreparationDependencies;
        after = storagePreparationDependencies;
        before = [
          "backup-vaultwarden.service"
          "vaultwarden.service"
        ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = lib.getExe importVaultwardenData;
        };
      };

      vaultwarden = {
        requires = vaultwardenDependencies;
        after = vaultwardenDependencies;
      };

      backup-vaultwarden = {
        environment.SHELLOPTS = "errexit:pipefail";
        wantedBy = lib.mkForce [ ];
        requires = backupDependencies;
        after = backupDependencies;
      };
    };

    timers.backup-vaultwarden.timerConfig = {
      OnCalendar = "*-*-* 06:05:00";
      Persistent = lib.mkForce false;
    };
  };
}
