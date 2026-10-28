{ inputs, ... }:
let
  inherit (import ./settings.nix) hostName;
in
{
  imports = [
    inputs.agenix.nixosModules.default
    ./boot.nix
    ./graphics.nix
    ./hardware-configuration.nix
    ./services
  ];

  networking.hostName = hostName;

  nix.settings = {
    min-free = 5 * 1024 * 1024 * 1024;
    max-free = 10 * 1024 * 1024 * 1024;
  };

  system.stateVersion = "26.05";
}
