{ lib, ... }:
{
  imports = [
    ../citrus
    ./ssh.nix
    ./hardware-configuration.nix
    ./image.nix
    ./graphics.nix
  ];

  networking.hostName = lib.mkForce "citrus-vm";
  nix.settings = {
    max-jobs = lib.mkForce 1;
    cores = lib.mkForce 4;
  };
}
