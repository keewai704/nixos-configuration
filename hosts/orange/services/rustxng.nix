{ inputs, ... }:
let
  inherit (import ../settings.nix) rustxngPort;
in
{
  system.extraDependencies = [ inputs.rustxng-release.outPath ];

  orange.healthMonitor = {
    userUnits = [ "rustxng.service" ];
    loopbackPorts = [ rustxngPort ];
  };

  home-manager.users.keewai.services.rustxng = {
    enable = true;
    port = rustxngPort;
  };
}
