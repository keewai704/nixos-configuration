{
  imports = [
    ./dconf.nix
    ./desktop-scheduling.nix
    ./hyprland-package.nix
    ./hyprlock.nix
    ./input-method-shortcut.nix
  ];

  home-manager.users.keewai.imports = [ ../home/keewai/desktop ];

  nixpkgs.config.allowUnfreePackages = [ "chatgpt-desktop" ];
}
