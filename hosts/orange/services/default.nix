{ lib, ... }:
{
  imports = [
    ./apple-device-usb.nix
    ./health-monitor
    ./immich
    ./jellyfin
    ./local-backup
    ./maintenance.nix
    ./minecraft.nix
    ./rustxng.nix
    ./samba.nix
    ./smart-tests.nix
    ./storage.nix
    ./t3code.nix
    ./tailscale-exit-node.nix
    ./tv
    ./vaultwarden
    ./web
  ];

  _module.args.fillTemplate =
    file: replacements:
    lib.replaceStrings (lib.attrNames replacements) (lib.attrValues replacements) (
      builtins.readFile file
    );
}
