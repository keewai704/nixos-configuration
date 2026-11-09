{ config, inputs, ... }:
{
  boot = {
    kernelPackages = inputs.nix-cachyos-kernel.legacyPackages.x86_64-linux.linuxPackages-cachyos-latest;
    loader = {
      systemd-boot = {
        enable = true;
        configurationLimit = 10;
      };
      efi.canTouchEfiVariables = true;
    };
    supportedFilesystems = [ "zfs" ];
    zfs = {
      package = config.boot.kernelPackages.zfs_cachyos;
      forceImportRoot = false;
    };
  };
}
