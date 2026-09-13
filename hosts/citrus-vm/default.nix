{ lib, ... }:
{
  imports = [
    ../citrus
    ./access.nix
    ./hardware-configuration.nix
    ./desktop.nix
  ];

  networking.hostName = lib.mkForce "citrus-vm";
  nix.settings = {
    max-jobs = lib.mkForce 1;
    cores = lib.mkForce 4;
  };
}
