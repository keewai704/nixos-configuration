{
  lib,
  orangeSettings,
  pkgs,
  ...
}:

let
  inherit (orangeSettings)
    immichMediaRoot
    lanInterface
    storageMountUnit
    storageRoot
    vaultwardenBackupRoot
    ;
in
{
  # This disk already contains the previous Immich and Vaultwarden data. It is
  # intentionally mounted without formatting or repartitioning.
  fileSystems.${storageRoot} = {
    device = "/dev/disk/by-uuid/8d14b091-590e-414a-aa82-dd0670742792";
    fsType = "ext4";
    options = [
      "noatime"
      "nodev"
      "nosuid"
    ];
  };

  # Publish the HDD on the trusted LAN and tailnet only. NetBIOS discovery is
  # useful on the LAN; tailnet clients connect directly over modern SMB/445.
  networking.firewall.interfaces = {
    ${lanInterface} = {
      allowedTCPPorts = [
        139
        445
      ];
      allowedUDPPorts = [
        137
        138
      ];
    };
    tailscale0.allowedTCPPorts = [ 445 ];
  };

  services.samba = {
    enable = true;
    winbindd.enable = false;
    settings = {
      global = {
        "map to guest" = "Bad User";
      };

      storage = {
        path = storageRoot;
        comment = "Orange HDD storage";
        "guest ok" = "yes";
        "guest only" = "yes";
        "read only" = "no";
        "force user" = "keewai";
        "force group" = "immich-media";
        "create mask" = "0664";
        "directory mask" = "0775";
        "veto files" = "/server/lost+found/";
      };
    };
  };

  systemd = {
    tmpfiles = {
      rules = [
        "d /var/lib/vaultwarden 0700 vaultwarden vaultwarden -"
        "z ${storageRoot} 0775 keewai immich-media -"
      ];

      settings = {
        # The mount root is intentionally owned by keewai, so tmpfiles rejects
        # Vaultwarden's root-owned child path as an unsafe transition. The
        # mount-ordered media-storage-prepare service below creates it instead.
        "10-vaultwarden" = lib.mkForce { };

        # Override Immich's default 0700 mount-root rule. Existing files below
        # this directory already use gid 1000 and remain otherwise untouched.
        immich.${immichMediaRoot}.e = {
          user = lib.mkForce "keewai";
          group = lib.mkForce "immich-media";
          mode = lib.mkForce "0770";
        };
      };
    };

    services = {
      samba-smbd = {
        requires = [ storageMountUnit ];
        after = [ storageMountUnit ];
      };

      media-storage-prepare = {
        description = "Prepare mounted HDD directories for media services";
        requires = [ storageMountUnit ];
        after = [ storageMountUnit ];
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
