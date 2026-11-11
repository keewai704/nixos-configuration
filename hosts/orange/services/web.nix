let
  settings = import ../settings.nix;
in
{
  imports = [ (import ../../../modules/tailnet-web settings) ];

  orange.healthMonitor = {
    units = [
      "nginx.service"
      "tailscale-serve-nginx.service"
    ];
    loopbackPorts = [ settings.nginxPort ];
  };
}
