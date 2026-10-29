{
  fillTemplate,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ../../settings.nix)
    localBackupRoot
    minecraftDataDir
    minecraftLiveBackupRoot
    storageMountUnit
    storageRoot
    vaultwardenBackupRoot
    ;

  scriptReplacements = {
    "@localBackupRoot@" = lib.escapeShellArg localBackupRoot;
    "@minecraftArchivePath@" = lib.escapeShellArg (lib.removePrefix "/" minecraftDataDir);
    "@minecraftLiveBackupRoot@" = lib.escapeShellArg minecraftLiveBackupRoot;
    "@vaultwardenDatabase@" = lib.escapeShellArg "${vaultwardenBackupRoot}/db.sqlite3";
    "@vaultwardenBackupRoot@" = lib.escapeShellArg vaultwardenBackupRoot;
  };

  localBackup = pkgs.writeShellApplication {
    name = "orange-local-backup";
    runtimeInputs = with pkgs; [
      coreutils
      findutils
      gnutar
      jq
      systemd
      unzip
      zstd
    ];
    text = fillTemplate ./local-backup.sh scriptReplacements;
  };

in
{
  systemd.services = {
    orange-local-backup = {
      description = "Create versioned local backups of orange service state";
      startAt = "*-*-* 06:15:00";
      requires = [ storageMountUnit ];
      wants = [ "backup-vaultwarden.service" ];
      after = [
        "backup-vaultwarden.service"
        storageMountUnit
      ];
      serviceConfig = {
        Type = "oneshot";
        TimeoutStartSec = "20min";
        ExecStart = lib.getExe localBackup;
        UMask = "0077";
        Nice = 10;
        IOSchedulingClass = "idle";
        ReadWritePaths = [ "${storageRoot}/server/backups" ];
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
      };
    };
  };
}
