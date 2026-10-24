{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  latestPackages = pkgs.cachyosKernels.linuxPackages-cachyos-latest-lto;
  rcPackages = pkgs.cachyosKernels.linuxPackages-cachyos-rc-lto;
  rcBaseVersion = lib.versions.pad 3 (
    builtins.head (lib.splitString "-rc" rcPackages.kernel.version)
  );
  upstreamPackages =
    if lib.versionOlder latestPackages.kernel.version rcBaseVersion then rcPackages else latestPackages;
in
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

  boot.kernelPackages = upstreamPackages.extend (
    _final: previous: {
      kernel = previous.kernel.override {
        pname = "linux-cachyos-citrus";
        autoModules = false;
        processorOpt = "x86_64-v4";
        modDirVersion = "${lib.versions.pad 3 previous.kernel.version}-cachyos-citrus";
        extraMakeFlags = [ "KCFLAGS=-march=znver5 -mtune=znver5" ];
        structuredExtraConfig = import ./kernel-config.nix { inherit lib; };
      };
    }
  );
  boot.zfs.package = config.boot.kernelPackages.zfs_cachyos;
}
