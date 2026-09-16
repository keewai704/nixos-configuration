{
  imports = [
    ./dconf.nix
    ./hyprland-package.nix
  ];

  home-manager.users.keewai.imports = [ ../home/keewai/desktop ];

  nixpkgs.config.allowUnfreePackages = [ "chatgpt-desktop" ];
}
