let
  inherit (import ../settings.nix) rustxngPort;
in
{
  orange.healthMonitor = {
    userUnits = [ "rustxng.service" ];
    loopbackPorts = [ rustxngPort ];
  };

  home-manager.users.keewai.services.rustxng = {
    enable = true;
    port = rustxngPort;
  };
}
