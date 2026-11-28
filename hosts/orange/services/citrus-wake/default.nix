{
  lib,
  mkClientAllowlist,
  mkProxyLocation,
  pkgs,
  ...
}:
let
  inherit (import ../../settings.nix)
    citrusWakePort
    lanBroadcast
    tailnetHostname
    ;
  citrus = import ../../../citrus/settings.nix;

  museOnly = mkClientAllowlist "$citrus_wake_allowed" [
    "100.99.205.86"
    "fd7a:115c:a1e0::5f2c:cd57"
  ];

  citrusWake = pkgs.writers.writePython3Bin "citrus-wake" {
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./citrus-wake.py);
in
{
  orange.healthMonitor = {
    units = [ "citrus-wake.service" ];
    loopbackPorts = [ citrusWakePort ];
  };

  systemd.services.citrus-wake = {
    description = "Send Wake-on-LAN packets to Citrus and relay Immich machine learning";
    wants = [ "network-online.target" ];
    after = [
      "network-online.target"
      "tailscaled.service"
    ];
    wantedBy = [ "multi-user.target" ];
    environment = {
      CITRUS_WAKE_PORT = toString citrusWakePort;
      CITRUS_MAC = citrus.lanMac;
      CITRUS_LAN_BROADCAST = lanBroadcast;
      CITRUS_MACHINE_LEARNING_URL = "${citrus.tailnetOrigin}/immich-machine-learning";
      CITRUS_ALIVE_URL = "${citrus.tailnetOrigin}/immich-machine-learning-control/alive";
      SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt";
    };
    serviceConfig = {
      ExecStart = lib.getExe citrusWake;
      DynamicUser = true;
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };

  services.nginx = {
    appendHttpConfig = museOnly.map;

    virtualHosts.${tailnetHostname}.locations."= /wake/citrus" = mkProxyLocation {
      port = citrusWakePort;
      path = "/wake";
      extraConfig = museOnly.deny;
    };
  };
}
