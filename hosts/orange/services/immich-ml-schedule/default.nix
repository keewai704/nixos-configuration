{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ../../settings.nix)
    citrusWakePort
    immichPort
    ;
  citrus = import ../../../citrus/settings.nix;

  controlUrl = "${citrus.tailnetOrigin}/immich-machine-learning-control";

  schedule = pkgs.writers.writePython3Bin "immich-ml-schedule" {
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./immich-ml-schedule.py);

  mkService = description: mode: {
    inherit description;
    environment = {
      IMMICH_API_URL = "http://127.0.0.1:${toString immichPort}/api";
      CITRUS_WAKE_URL = "http://127.0.0.1:${toString citrusWakePort}/wake";
      CITRUS_ALIVE_URL = "${controlUrl}/alive";
      CITRUS_SUSPEND_URL = "${controlUrl}/suspend";
      SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt";
    };
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${lib.getExe schedule} ${mode}";
      DynamicUser = true;
      LoadCredential = "api-key:${config.age.secrets.immich-api-key.path}";
    };
  };
in
{
  age.secrets.immich-api-key = {
    file = ../../../../secrets/immich-api-key.age;
    mode = "0400";
  };

  systemd.tmpfiles.rules = [ "R /var/lib/immich-ml-schedule" ];

  systemd.services = {
    immich-ml-schedule = mkService "Run Immich machine learning on Citrus" "run" // {
      wants = [ "network-online.target" ];
      after = [
        "network-online.target"
        "tailscaled.service"
        "immich-server.service"
        "citrus-wake.service"
      ];
    };

    immich-ml-pause = mkService "Hold Immich machine learning queues until the schedule" "pause" // {
      wantedBy = [ "immich-server.service" ];
      after = [ "immich-server.service" ];
    };
  };

  systemd.timers.immich-ml-schedule = {
    wantedBy = [ "timers.target" ];
    timerConfig.OnCalendar = "Mon..Fri 09:00";
  };
}
