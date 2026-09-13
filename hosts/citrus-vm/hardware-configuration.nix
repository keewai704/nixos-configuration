{
  lib,
  pkgs,
  ...
}:
{
  disabledModules = [
    ../citrus/hardware-configuration.nix
    ../citrus/fingerprint.nix
    ../citrus/apple-device-usb.nix
  ];

  nixpkgs.hostPlatform = "x86_64-linux";
  boot = {
    loader = {
      limine.enable = lib.mkForce false;
      grub.enable = lib.mkForce false;
      systemd-boot.enable = lib.mkOverride 40 true;
      efi.canTouchEfiVariables = lib.mkForce false;
    };
    kernelPackages = lib.mkForce pkgs.linuxPackages;
    initrd.kernelModules = lib.mkForce [
      "hv_vmbus"
      "hv_storvsc"
      "hv_netvsc"
      "hv_utils"
      "hv_balloon"
    ];
    initrd.availableKernelModules = [ "sd_mod" ];
    kernelModules = [ "hyperv_drm" ];
  };

  hardware.bluetooth.enable = lib.mkForce false;
  services.blueman.enable = lib.mkForce false;
  zramSwap.enable = true;
}
