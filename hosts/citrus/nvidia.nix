{ lib, pkgs, ... }:
{
  nixpkgs.config.allowUnfreePredicate =
    package:
    builtins.elem (lib.getName package) [
      "cuda_cccl"
      "cuda_compat"
      "cuda_cudart"
      "cuda_nvcc"
      "cuda_nvml_dev"
      "cuda_nvrtc"
      "cudnn"
      "libcublas"
      "libcurand"
      "libnvvm"
      "nvidia-x11"
      "nvidia-settings"
    ];

  nix.settings = {
    extra-substituters = [
      "https://nix-community.cachix.org"
      "https://cache.nixos-cuda.org"
    ];
    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
    ];
  };

  boot.initrd.kernelModules = [
    "nvidia"
    "nvidia_modeset"
    "nvidia_uvm"
    "nvidia_drm"
  ];

  hardware.nvidia = {
    package = pkgs.nvidia_cachyos;
    open = true;
    modesetting.enable = true;
    powerManagement.enable = true;
  };

  services.xserver.videoDrivers = [ "nvidia" ];
  services.udev.extraRules = ''
    SUBSYSTEM=="drm", KERNEL=="card[0-9]*", KERNELS=="0000:01:00.0", SYMLINK+="dri/nvidia"
  '';
  environment.sessionVariables = {
    AQ_DRM_DEVICES = "/dev/dri/nvidia";
    LIBVA_DRIVER_NAME = "nvidia";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
  };
}
