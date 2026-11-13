{
  config,
  inputs,
  pkgs,
  ...
}:
{
  environment.systemPackages = [ pkgs.sbctl ];

  systemd.tmpfiles.rules = [ "w /sys/kernel/mm/lru_gen/min_ttl_ms - - - - 0" ];

  boot = {
    kernelPackages = inputs.nix-cachyos-kernel.legacyPackages.x86_64-linux.linuxPackages-cachyos-latest;
    loader = {
      limine = {
        enable = true;
        maxGenerations = 10;
        style.wallpapers = [ inputs.cachyos-limine-splash.outPath ];
        secureBoot = {
          enable = true;
          autoGenerateKeys = true;
          autoEnrollKeys.enable = true;
        };
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
