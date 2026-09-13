{
  imports = [
    ./dconf.nix
    ./hyprland-package.nix
    ./hyprlock.nix
  ];

  home-manager.users.keewai.imports = [ ../home/keewai/desktop ];

  nixpkgs.config.allowUnfreePackages = [ "chatgpt-desktop" ];
}
