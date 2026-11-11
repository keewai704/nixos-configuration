let
  settings = import ../settings.nix;
in
{
  imports = [ (import ../../../modules/tailnet-web/t3code.nix settings) ];

  orange.healthMonitor = {
    userUnits = [ "t3code.service" ];
    loopbackPorts = [ settings.t3codePort ];
  };
}
