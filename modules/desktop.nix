{
  imports = [
    ./dconf.nix
    ./desktop-scheduling.nix
    ./hyprland-package.nix
    ./input-method-shortcut.nix
  ];

  home-manager.users.keewai.imports = [ ../home/keewai/desktop ];
}
