{ inputs, lib, ... }:
let
  inherit (import ./settings.nix) hostName;
in
{
  imports = [
    inputs.agenix.nixosModules.default
    ./boot.nix
    ./hardware-configuration.nix
    ./services/health-monitor.nix
    ./services/immich.nix
    ./services/local-backup.nix
    ./services/maintenance.nix
    ./services/minecraft.nix
    ./services/obsidian-livesync.nix
    ./services/samba.nix
    ./services/smart-tests.nix
    ./services/storage.nix
    ./services/t3code.nix
    ./services/tailscale-exit-node.nix
    ./services/tv
    ./services/vaultwarden.nix
    ./services/web.nix
  ];

  _module.args.fillTemplate =
    file: replacements:
    lib.replaceStrings (lib.attrNames replacements) (lib.attrValues replacements) (
      builtins.readFile file
    );

  networking.hostName = hostName;

  nix.settings = {
    min-free = 5 * 1024 * 1024 * 1024;
    max-free = 10 * 1024 * 1024 * 1024;
  };

  system.stateVersion = "26.05";
}
