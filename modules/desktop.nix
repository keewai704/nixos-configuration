{
  imports = [
    ./dconf.nix
    ./hyprland-package.nix
    ./hyprlock.nix
  ];

  home-manager.users.keewai.imports = [ ../home/keewai/desktop ];

  # The desktop Home Manager profile includes the proprietary desktop client.
  nixpkgs.config.allowUnfreePackages = [ "chatgpt-desktop" ];
}
