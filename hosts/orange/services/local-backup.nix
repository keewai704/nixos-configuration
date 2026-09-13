{ lib, pkgs, ... }:
let
  inherit (import ../settings.nix)
    localBackupRoot
    minecraftDataDir
    storageMountUnit
    storageRoot
    vaultwardenBackupRoot
    ;

  scriptReplacements = {
    "@localBackupRoot@" = lib.escapeShellArg localBackupRoot;
    "@minecraftArchivePath@" = lib.escapeShellArg (lib.removePrefix "/" minecraftDataDir);
    "@vaultwardenDatabase@" = lib.escapeShellArg "${vaultwardenBackupRoot}/db.sqlite3";
    "@vaultwardenBackupRoot@" = lib.escapeShellArg vaultwardenBackupRoot;
  };

  localBackup = pkgs.writeShellApplication {
    name = "orange-local-backup";
    runtimeInputs = with pkgs; [
      coreutils
      findutils
      gnutar
      systemd
      zstd
    ];
    text = lib.replaceStrings (lib.attrNames scriptReplacements) (lib.attrValues scriptReplacements) (
      builtins.readFile ./local-backup.sh
    );
  };

in
{
  systemd.services = {
    orange-local-backup = {
      description = "Create versioned local backups of orange service state";
      startAt = "*-*-* 06:15:00";
      requires = [ storageMountUnit ];
      after = [
        "backup-vaultwarden.service"
        storageMountUnit
      ];
      serviceConfig = {
        Type = "oneshot";
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
