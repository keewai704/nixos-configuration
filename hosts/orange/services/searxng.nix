_:
let
  inherit (import ../settings.nix) searxngPort;
in
{
  orange.healthMonitor = {
    userUnits = [ "searxng.service" ];
    loopbackPorts = [ searxngPort ];
  };

  home-manager.users.keewai.services.searxng = {
    enable = true;
    port = searxngPort;
  };
}
