{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
{
  imports = [ ./bitwarden.nix ];

  nixpkgs.config.allowUnfreePredicate =
    package:
    builtins.elem (lib.getName package) [
      "chatgpt-desktop"
      "cuda_nvml_dev"
      "nvidia-x11"
      "nvidia-settings"
    ];

  programs = {
    dconf.enable = true;

    gamescope = {
      enable = true;
      enableWsi = true;
    };

    steam = {
      enable = true;
      package = inputs.millennium.packages.${pkgs.stdenv.hostPlatform.system}.millennium-steam;
      # Preserve Steam's FHS font set when personal fonts move to Home Manager.
      fontPackages = config.stylix.fonts.packages ++ [ pkgs.noto-fonts ] ++ config.fonts.packages;
      extraPackages = [ pkgs.gamescope ];
      extraCompatPackages = [ pkgs.proton-ge-bin ];
    };

  };

  services = {
    gnome.at-spi2-core.enable = true;
    gnome.gnome-keyring.enable = true;
    gvfs.enable = true;
    tumbler.enable = true;
  };

}
