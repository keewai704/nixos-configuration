{
  lib,
  pkgs,
  modulesPath,
  ...
}:
{
  disabledModules = [
    ../citrus/hardware-configuration.nix
    ../citrus/fingerprint.nix
    ../citrus/ipad.nix
  ];
  imports = [ (modulesPath + "/virtualisation/hyperv-image.nix") ];

  nixpkgs.hostPlatform = "x86_64-linux";
  image.baseName = "citrus-vm";
  virtualisation.diskSize = 128 * 1024;

  nixpkgs.overlays = [
    (_final: prev: {
      lkl = prev.lkl.overrideAttrs (old: {
        postPatch = old.postPatch + ''
          substituteInPlace tools/lkl/cptofs.c \
            --replace-fail 'lkl_start_kernel("mem=100M")' 'lkl_start_kernel("mem=1024M")'
        '';
      });
    })
  ];

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
