{ lib, pkgs, ... }:
let
  tuners = import ./tuners.nix;
  receiverUnits = map (tuner: "torne-receiver-${tuner.id}.service") tuners;
in
{
  services.pcscd = {
    enable = true;
    package = pkgs.pcsclite;
    readerConfigs = map (tuner: ''
      FRIENDLYNAME "Sony CECH-ZD1 J ${tuner.id} Smart Card Reader"
      DEVICENAME /run/torne-${tuner.id}/card.sock
      LIBPATH ${pkgs.local.torne-receiver}/lib/libifd_torne.so
      CHANNELID ${tuner.id}
    '') tuners;
  };

  systemd.services = {
    pcscd = {
      requires = receiverUnits;
      after = receiverUnits;
      bindsTo = receiverUnits;
      serviceConfig.SupplementaryGroups = [ "tv" ];
    };
  }
  // lib.listToAttrs (
    map (tuner: {
      name = "torne-receiver-${tuner.id}";
      value = {
        description = "Persistent direct USB control for Sony CECH-ZD1 J at ${tuner.usbPort}";
        wantedBy = [ "multi-user.target" ];
        postStart = ''
          for attempt in {1..600}; do
            if test -S /run/torne-${tuner.id}/control.sock && test -S /run/torne-${tuner.id}/card.sock; then
              exit 0
            fi
            sleep 0.1
          done
          exit 1
        '';
        serviceConfig = {
          User = "tv";
          Group = "tv";
          RuntimeDirectory = "torne-${tuner.id}";
          RuntimeDirectoryMode = "0750";
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          UMask = "0007";
          Restart = "on-failure";
          RestartSec = "5s";
          ExecStart = "${lib.getExe pkgs.local.torne-receiver} daemon --device ${tuner.usbPort} --socket-dir /run/torne-${tuner.id}";
          TimeoutStartSec = "65s";
          TimeoutStopSec = "10s";
        };
      };
    }) tuners
  );
}
