{ osConfig, ... }:
let
  tailnetHostname = "${osConfig.networking.hostName}.tail1e65cd.ts.net";
in
{
  systemd.user.services.paseo.Service.Environment = [
    "PASEO_HOSTNAMES=${tailnetHostname}"
    "PASEO_APP_BASE_URL=https://${tailnetHostname}"
  ];
}
