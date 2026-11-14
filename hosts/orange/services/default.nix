{ lib, ... }:
{
  imports = [
    ./citrus-wake
    ./health-monitor
    ./immich.nix
    ./immich-ml-schedule
    ./local-backup
    ./maintenance.nix
    ./samba.nix
    ./searxng.nix
    ./smart-tests.nix
    ./storage.nix
    ./t3code.nix
    ./tailscale-exit-node.nix
    ./tv
    ./vaultwarden.nix
    ./web.nix
  ];

  _module.args.fillTemplate =
    file: replacements:
    lib.replaceStrings (lib.attrNames replacements) (lib.attrValues replacements) (
      builtins.readFile file
    );
}
