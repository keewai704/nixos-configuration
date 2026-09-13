{
  lib,
  pkgs,
  ...
}:

let
  inherit (import ../settings.nix)
    immichMediaRoot
    storageMountUnit
    storageRoot
    vaultwardenBackupRoot
    ;
  storageDependencies = [ storageMountUnit ];
in
{
  fileSystems.${storageRoot} = {
    device = "/dev/disk/by-uuid/8d14b091-590e-414a-aa82-dd0670742792";
    fsType = "ext4";
    options = [
      "noatime"
      "nodev"
      "nosuid"
    ];
  };

  systemd = {
    tmpfiles = {
      rules = [
        "z ${storageRoot} 0775 keewai immich-media -"
      ];
    };

    services = {
      media-storage-prepare = {
        description = "Prepare mounted HDD directories for media services";
        requires = storageDependencies;
        after = storageDependencies;
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          ${pkgs.coreutils}/bin/install \
            --directory \
            --mode 0770 \
            --owner keewai \
            --group immich-media \
            ${lib.escapeShellArg immichMediaRoot}

          ${pkgs.coreutils}/bin/install \
            --directory \
            --mode 0770 \
            --owner vaultwarden \
            --group vaultwarden \
            ${lib.escapeShellArg vaultwardenBackupRoot}
        '';
      };
    };
  };
}
