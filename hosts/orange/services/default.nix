{ lib, ... }:
{
  imports = [
    ./health-monitor
    ./immich
    ./local-backup
    ./maintenance.nix
    ./minecraft.nix
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
