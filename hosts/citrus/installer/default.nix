{
  inputs,
  lib,
  ...
}:
{
  imports = [
    "${inputs.nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-base.nix"
    ../boot.nix
    ../desktop
    ../graphics.nix
  ];

  isoImage.edition = "citrus";

  nixpkgs.hostPlatform = "x86_64-linux";

  networking = {
    hostName = "citrus-installer";
    hostId = "175be74a";
  };

  users.users.keewai.initialPassword = "citrus";

  programs.steam.enable = lib.mkForce false;
  system.installer.channel.enable = false;
}
