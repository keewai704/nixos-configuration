{
  config,
  inputs,
  pkgs,
  ...
}:
{
  nixpkgs.overlays = [ inputs.nix-cachyos-kernel.overlays.pinned ];

  nix.settings = {
    extra-substituters = [ "https://cache.xinux.uz" ];
    extra-trusted-public-keys = [
      "cache.xinux.uz:BXCrtqejFjWzWEB9YuGB7X2MV4ttBur1N8BkwQRdH+0="
    ];
  };

  boot.initrd = {
    includeDefaultModules = false;
    availableKernelModules = [
      "atkbd"
      "autofs"
      "efivarfs"
      "hid_apple"
      "hid_generic"
      "hid_logitech_dj"
      "hid_logitech_hidpp"
      "i8042"
    ];
  };

  boot.kernelPackages = pkgs.cachyosKernels.linuxPackages-cachyos-latest-lto;
  boot.zfs.package = config.boot.kernelPackages.zfs_cachyos;
}
