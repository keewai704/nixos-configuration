{
  config,
  lib,
  modulesPath,
  ...
}:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot = {
    initrd = {
      availableKernelModules = [
        "nvme"
        "xhci_pci_prom21"
        "ahci"
        "xhci_pci"
        "usbhid"
        "usb_storage"
        "sd_mod"
      ];
      kernelModules = [ ];
    };
    kernelModules = [ "kvm-amd" ];
    extraModulePackages = [ ];
  };

  fileSystems = {
    "/" = {
      device = "/dev/disk/by-label/citrus-root";
      fsType = "btrfs";
      options = [
        "subvol=@root"
        "compress=zstd:3"
        "noatime"
      ];
    };

    "/home" = {
      device = "/dev/disk/by-label/citrus-root";
      fsType = "btrfs";
      options = [
        "subvol=@home"
        "compress=zstd:3"
        "noatime"
      ];
    };

    "/nix" = {
      device = "/dev/disk/by-label/citrus-root";
      fsType = "btrfs";
      options = [
        "subvol=@nix"
        "compress=zstd:3"
        "noatime"
      ];
    };

    "/boot" = {
      device = "/dev/disk/by-label/CITRUS_EFI";
      fsType = "vfat";
      options = [
        "fmask=0077"
        "dmask=0077"
      ];
    };

    "/swap" = {
      device = "/dev/disk/by-label/citrus-root";
      fsType = "btrfs";
      options = [
        "subvol=@swap"
        "noatime"
      ];
    };
  };

  swapDevices = [
    {
      device = "/swap/swapfile";
      size = 16 * 1024;
      priority = 10;
    }
  ];

  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
    priority = 100;
  };

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
