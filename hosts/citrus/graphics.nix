{ config, lib, ... }:
{
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    modesetting.enable = true;
    open = true;
    package = config.boot.kernelPackages.nvidiaPackages.legacy_580;
  };

  assertions = [
    {
      assertion = lib.versions.major config.hardware.nvidia.package.version == "580";
      message = "citrus pins the NVIDIA driver to the 580 series";
    }
  ];
}
