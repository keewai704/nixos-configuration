{
  imports = [ ./wsl.nix ];

  networking.hostName = "citrus";
  nixpkgs.hostPlatform = "x86_64-linux";
  system.stateVersion = "26.05";

  home-manager.users.keewai.imports = [ ../../home/keewai/wsl ];
}
