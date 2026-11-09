{ lib, pkgs, ... }:
let
  inherit (import ../../settings.nix)
    citrusWakePort
    lanBroadcast
    tailnetHostname
    ;
  citrus = import ../../../citrus/settings.nix;
  mkProxyLocation = import ../web/proxy.nix;

  museAddresses = [
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
    appendHttpConfig = ''
      map $tailscale_client_ip $citrus_wake_allowed {
        default 0;
        ${lib.concatMapStrings (address: ''
          "${address}" 1;
        '') museAddresses}
      }
    '';

    virtualHosts.${tailnetHostname}.locations."= /wake/citrus" =
      mkProxyLocation citrusWakePort ''
        if ($citrus_wake_allowed = 0) {
          return 403;
        }
      ''
      // {
        proxyPass = "http://127.0.0.1:${toString citrusWakePort}/wake";
      };
  };
}
