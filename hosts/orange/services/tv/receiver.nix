{ lib, pkgs, ... }:
{
  services.pcscd = {
    enable = true;
    package = pkgs.pcsclite;
    readerConfigs = [
      ''
        FRIENDLYNAME "Sony CECH-ZD1 J Smart Card Reader"
        DEVICENAME /run/torne/card.sock
        LIBPATH ${pkgs.local.torne-receiver}/lib/libifd_torne.so
        CHANNELID 0
      ''
    ];
  };

  systemd.services.pcscd = {
    requires = [ "torne-receiver.service" ];
    after = [ "torne-receiver.service" ];
    bindsTo = [ "torne-receiver.service" ];
    serviceConfig.SupplementaryGroups = [ "tv" ];
  };

  systemd.services.torne-receiver = {
    description = "Persistent direct USB control for Sony CECH-ZD1 J";
    wantedBy = [ "multi-user.target" ];
    postStart = ''
      for attempt in {1..600}; do
        if test -S /run/torne/capture.sock && test -S /run/torne/card.sock; then
          exit 0
        fi
        sleep 0.1
      done
      exit 1
    '';
    serviceConfig = {
      User = "tv";
      Group = "tv";
      RuntimeDirectory = "torne";
      RuntimeDirectoryMode = "0750";
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      UMask = "0007";
      Restart = "on-failure";
      RestartSec = "5s";
      ExecStart = "${lib.getExe pkgs.local.torne-receiver} daemon";
      TimeoutStartSec = "65s";
      TimeoutStopSec = "10s";
    };
  };
}
