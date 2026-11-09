let
  inherit (import ./settings.nix) hostName;
in
{
  imports = [
    ./boot.nix
    ./desktop
    ./graphics.nix
    ./hardware-configuration.nix
    ./services
  ];

  networking = {
    inherit hostName;
    hostId = "175be74a";
  };

  system.stateVersion = "26.05";
}
