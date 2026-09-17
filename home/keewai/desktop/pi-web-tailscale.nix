{ osConfig, ... }:
{
  systemd.user.services.pi-web.Service.Environment = [
    "PI_WEB_ALLOWED_HOSTS=${osConfig.networking.hostName}.tail1e65cd.ts.net"
  ];
}
