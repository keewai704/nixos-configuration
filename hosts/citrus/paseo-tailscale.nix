{ config, lib, ... }:
let
  tailscale = lib.getExe config.services.tailscale.package;
in
{
  systemd.services.tailscale-serve-paseo = {
    description = "Publish Paseo over tailnet HTTPS";
    requires = [ "tailscaled.service" ];
    wants = [
      "network-online.target"
      "tailscaled-set.service"
      "home-manager-keewai.service"
    ];
    after = [
      "network-online.target"
      "tailscaled.service"
      "tailscaled-set.service"
      "home-manager-keewai.service"
    ];
    partOf = [ "tailscaled.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = "5s";
      TimeoutStartSec = "30s";
      ExecStart = "${tailscale} serve --bg --yes --https=443 http://127.0.0.1:6767";
      ExecStop = "${tailscale} serve --https=443 off";
    };
  };
}
