{ lib, ... }:

{
  fileSystems = {
    "/" = {
      device = "/dev/disk/by-uuid/666b9a83-5f6d-4712-83c7-5fd3f06d0205";
      fsType = "xfs";
    };

    "/boot" = {
      device = "/dev/disk/by-uuid/916D-9CAB";
      fsType = "vfat";
      options = [
        "fmask=0077"
        "dmask=0077"
      ];
    };
  };

  swapDevices = [
    { device = "/dev/disk/by-uuid/42d9164d-ee11-4ce8-af90-d25877ef9ec6"; }
  ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  virtualisation.hypervGuest.enable = true;
}
