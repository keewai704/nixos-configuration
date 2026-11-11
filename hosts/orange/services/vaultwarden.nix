{ lib, ... }:

let
  inherit (import ../settings.nix)
    storageMountUnit
    tailnetHostname
    tailnetOrigin
    vaultwardenBackupRoot
    vaultwardenPort
    ;
  mkProxyLocation = import ../../../modules/tailnet-web/proxy.nix;
  backupDependencies = [
    "media-storage-prepare.service"
    storageMountUnit
  ];
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
    tmpfiles.settings."10-vaultwarden" = lib.mkForce { };

    services = {
      vaultwarden = {
        requires = [ storageMountUnit ];
        after = [ storageMountUnit ];
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
