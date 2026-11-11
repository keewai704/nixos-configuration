{ lib, ... }:
{
  nix = {
    daemonIOSchedClass = "idle";
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 14d";
    };

    optimise.automatic = true;

    settings = {
      always-allow-substitutes = true;
      narinfo-cache-negative-ttl = 0;
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      extra-substituters = [
        "https://nix-community.cachix.org"
      ];
      extra-trusted-public-keys = [
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];
    };
  };

  systemd.slices.nix.sliceConfig = {
    CPUWeight = 20;
    MemoryHigh = lib.mkDefault "2G";
  };

  systemd.services.nix-daemon.serviceConfig.Slice = "nix.slice";
  systemd.services.nix-gc.serviceConfig = {
    Slice = "nix.slice";
    IOSchedulingClass = "idle";
  };
}
