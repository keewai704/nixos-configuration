{ pkgs, ... }:
{
  boot.kernelPackages = pkgs.linuxPackagesFor (
    pkgs.callPackage ../../pkgs/kernel-drivers/linux.nix { }
  );
}
