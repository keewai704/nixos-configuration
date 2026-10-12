{ config, ... }:
{
  boot.extraModulePackages = [
    (config.boot.kernelPackages.callPackage ../../pkgs/xpad-beitong { })
  ];
}
