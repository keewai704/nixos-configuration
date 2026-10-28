{ lib, pkgs, ... }:
let
  inherit (import ./settings.nix)
    storageRoot
    storageMountUnit
    televisionRoot
    recordings
    captures
    ;
in
{
  imports = [
    ./receiver.nix
    ./mirakc.nix
    ./edcb.nix
    ./recording.nix
    ./konomitv.nix
  ];

  users.groups.tv = { };
  users.users.keewai.extraGroups = [ "tv" ];
  users.users.tv = {
    isSystemUser = true;
    group = "tv";
    extraGroups = [
      "video"
      "render"
    ];
    home = "/var/lib/edcb";
  };

  services.udev.extraRules = ''
    SUBSYSTEM=="usb", ATTR{idVendor}=="054c", ATTR{idProduct}=="04b2", MODE="0660", GROUP="tv"
  '';

  systemd.services = {
    tv-storage-prepare = {
      description = "Prepare television recording and capture directories on the HDD";
      requires = [ storageMountUnit ];
      after = [ storageMountUnit ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ReadWritePaths = [ storageRoot ];
        ExecStart = "${pkgs.coreutils}/bin/install --directory --mode=0770 --owner=tv --group=tv ${
          lib.escapeShellArgs [
            televisionRoot
            recordings
            captures
          ]
        }";
      };
    };
  };
}
