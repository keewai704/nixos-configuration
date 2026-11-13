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
        resolution = "5120x2160";
        style = {
          wallpapers = [ inputs.cachyos-limine-splash.outPath ];
          interface.resolution = "5120x2160";
          graphicalTerminal.font.scale = "2x2";
        };
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
