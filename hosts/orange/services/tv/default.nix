{
  lib,
  pkgs,
  mkProxyLocation,
  ...
}:
let
  inherit (import ../../settings.nix)
    storageRoot
    storageMountUnit
    tailnetHostname
    tailnetOrigin
    ;
  recordings = "${storageRoot}/TV/Recordings";
  captures = "${storageRoot}/TV/Captures";
  keepAliveSeconds = 120;
  ini = pkgs.formats.ini { };
  edcbSettings = {
    "Common.ini" = ini.generate "Common.ini" {
      SET = {
        DataSavePath = "/var/lib/edcb/Setting";
        RecFolderNum = 1;
        RecFolderPath0 = recordings;
        RecExePath = "${pkgs.local.edcb}/bin/EpgDataCap_Bon";
      };
    };
    "EpgTimerSrv.ini" = ini.generate "EpgTimerSrv.ini" {
      SET = {
        EnableTCPSrv = 1;
        TCPPort = 4510;
        TCPIPv6 = 0;
        TCPAccessControlList = "+127.0.0.1";
        EnableHttpSrv = 0;
        SaveDebugLog = 1;
        CompatFlags = 4095;
      };
      "BonDriver_coax.so" = {
        Count = 1;
        GetEpg = 1;
        EPGCount = 1;
        Priority = 1;
      };
      TVTEST = {
        Num = 1;
        "0" = "BonDriver_coax.so";
      };
      EPG_CAP = {
        Count = 1;
        "0" = "04:00";
        "0Select" = 1;
      };
    };
    "EpgDataCap_Bon.ini" = ini.generate "EpgDataCap_Bon.ini" {
      SET = {
        OpenWait = 0;
        SaveLogo = 1;
        SaveLogoTypeFlags = 63;
        TraceBonDriverLevel = 2;
      };
      SET_TCP = {
        Count = 1;
        IP0 = 1;
        Port0 = 0;
      };
    };
  };
  bonDriverConfig = ini.generate "BonDriver_coax.ini" {
    coax = {
      Host = "/run/coax/http.sock";
      StartDaemon = 0;
    };
    Tuners.terrestrial = "ISDBT, cech-zd1j:*, bands=UHF";
    Spaces."0" = "地デジ, terrestrial";
  };
  konomitvConfig = (pkgs.formats.yaml { }).generate "konomitv.yaml" {
    general = {
      backend = "EDCB";
      edcb_url = "tcp://127.0.0.1:4510/";
      encoder = "QSVEncC";
    };
    server.port = 7000;
    tv.max_alive_time = keepAliveSeconds;
    video.recorded_folders = [ recordings ];
    capture.upload_folders = [ captures ];
  };
  tvEnvironment = {
    COAXD_SOCKET = "/run/coax/http.sock";
    COAXD_SOCKET_DIR = "/run/coax";
    PCSCLITE_CSOCK_NAME = "/run/coax/pcscd.comm";
  };
  serviceDefaults = {
    User = "tv";
    Group = "tv";
    NoNewPrivileges = true;
    ProtectSystem = "strict";
    ProtectHome = true;
    PrivateTmp = true;
    Restart = "on-failure";
    RestartSec = "5s";
    UMask = "0007";
  };
in
{
  users.groups.tv = { };
  users.users.tv = {
    isSystemUser = true;
    group = "tv";
    extraGroups = [
      "video"
      "render"
    ];
    home = "/var/lib/edcb";
  };

  services.udev.extraRules = ''
    SUBSYSTEM=="usb", ATTR{idVendor}=="054c", ATTR{idProduct}=="04b2", MODE="0660", GROUP="tv"
  '';

  systemd.services = {
    tv-storage-prepare = {
      description = "Prepare television recording and capture directories on the HDD";
      requires = [ storageMountUnit ];
      after = [ storageMountUnit ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ReadWritePaths = [ storageRoot ];
        ExecStart = "${pkgs.coreutils}/bin/install --directory --mode=0770 --owner=tv --group=tv ${
          lib.escapeShellArgs [
            "${storageRoot}/TV"
            recordings
            captures
          ]
        }";
      };
    };

    coaxd = {
      description = "USB tuner host for the Sony CECH-ZD1 J";
      wantedBy = [ "multi-user.target" ];
      environment = tvEnvironment;
      postStart = ''
        for attempt in {1..100}; do
          if ${pkgs.local.coax}/bin/coax list --no-start >/dev/null 2>&1; then
            exit 0
          fi
          sleep 0.1
        done
        exit 1
      '';
      serviceConfig = serviceDefaults // {
        RuntimeDirectory = "coax";
        RuntimeDirectoryMode = "0750";
        ExecStart = "${pkgs.local.coax}/bin/coaxd --idle 0 --socket-dir /run/coax";
      };
    };

    coax-pcsc = {
      description = "Expose the tuner's B-CAS slot to PC/SC clients";
      wantedBy = [ "multi-user.target" ];
      requires = [ "coaxd.service" ];
      after = [ "coaxd.service" ];
      environment = tvEnvironment;
      postStart = ''
        for attempt in {1..100}; do
          test ! -S /run/coax/pcscd.comm || exit 0
          sleep 0.1
        done
        exit 1
      '';
      serviceConfig = serviceDefaults // {
        ReadWritePaths = [ "/run/coax" ];
        ExecStart = "${pkgs.local.coax}/bin/coax pcsc --idle 0 --no-start";
      };
    };

    edcb-setup = {
      description = "Prepare native EDCB and scan the terrestrial tuner on first start";
      requires = [
        "coaxd.service"
        "coax-pcsc.service"
        "tv-storage-prepare.service"
      ];
      after = [
        "coaxd.service"
        "coax-pcsc.service"
        "tv-storage-prepare.service"
      ];
      environment = tvEnvironment;
      path = [
        pkgs.coreutils
        pkgs.findutils
        pkgs.local.edcb
      ];
      serviceConfig =
        (builtins.removeAttrs serviceDefaults [
          "Restart"
          "RestartSec"
        ])
        // {
          Type = "oneshot";
          RemainAfterExit = true;
          StateDirectory = "edcb";
          ReadWritePaths = [ recordings ];
          TimeoutStartSec = "2h";
        };
      script = ''
        install -d -m 0770 /var/lib/edcb/Setting /var/lib/edcb/lib
        ln -sfn ${pkgs.local.bondriver-coax}/lib/BonDriver_coax.so /var/lib/edcb/lib/BonDriver_coax.so
        ln -sfn ${bonDriverConfig} /var/lib/edcb/lib/BonDriver_coax.ini
        for plugin in ${pkgs.local.edcb}/lib/edcb/*.so ${pkgs.local.b25-decoder}/lib/edcb/*.so; do
          ln -sfn "$plugin" "/var/lib/edcb/lib/$(basename "$plugin")"
        done
        for file in ${pkgs.local.edcb}/share/edcb/*.ini ${pkgs.local.edcb}/share/edcb/*.txt; do
          test -e "/var/lib/edcb/$(basename "$file")" || cp "$file" /var/lib/edcb/
        done
        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (name: file: ''
            ${pkgs.python3}/bin/python ${./configure-edcb.py} ${file} /var/lib/edcb/${name}
          '') edcbSettings
        )}
        if ! test -s /var/lib/edcb/Setting/ChSet5.txt ||
          test -z "$(find /var/lib/edcb/Setting -name 'BonDriver_coax*.ChSet4.txt' -size +0c -print -quit)"; then
          EpgDataCap_Bon -d BonDriver_coax.so -chscan
          test -s /var/lib/edcb/Setting/ChSet5.txt
          test -n "$(find /var/lib/edcb/Setting -name 'BonDriver_coax*.ChSet4.txt' -size +0c -print -quit)"
        fi
        if ! test -e /var/lib/edcb/.initial-epg-complete; then
          EpgDataCap_Bon -d BonDriver_coax.so -epgcap
          test -n "$(find /var/lib/edcb/Setting/EpgData -name '*_epg.dat' -size +0c -print -quit)"
          touch /var/lib/edcb/.initial-epg-complete
        fi
      '';
    };

    edcb = {
      description = "Native xtne6f EDCB recording and EPG server";
      restartTriggers = lib.attrValues edcbSettings;
      wantedBy = [ "multi-user.target" ];
      requires = [ "edcb-setup.service" ];
      after = [ "edcb-setup.service" ];
      environment = tvEnvironment;
      postStart = ''
        ${pkgs.python3}/bin/python - <<'PY'
        import socket
        import time
        for attempt in range(300):
            try:
                with socket.create_connection(('127.0.0.1', 4510), timeout=1):
                    break
            except OSError:
                time.sleep(0.1)
        else:
            raise SystemExit('EDCB TCP control listener did not start')
        PY
      '';
      serviceConfig = serviceDefaults // {
        StateDirectory = "edcb";
        WorkingDirectory = "/var/lib/edcb";
        ReadWritePaths = [ recordings ];
        ExecStart = "${pkgs.local.edcb}/bin/EpgTimerSrv";
        TimeoutStopSec = "50s";
      };
    };

    konomitv = {
      description = "KonomiTV television and recording frontend";
      wantedBy = [ "multi-user.target" ];
      requires = [
        "edcb.service"
        storageMountUnit
      ];
      after = [
        "edcb.service"
        storageMountUnit
      ];
      environment = {
        LIBVA_DRIVER_NAME = "iHD";
      };
      serviceConfig = serviceDefaults // {
        StateDirectory = "konomitv";
        LogsDirectory = "konomitv";
        ReadWritePaths = [
          recordings
          captures
        ];
        ExecStart = lib.getExe pkgs.local.konomitv;
        TimeoutStopSec = "60s";
      };
      preStart = ''
        install -d -m 0770 /var/lib/konomitv/data/{account-icons,thumbnails,twitter-debug-screenshots}
        test -e /var/lib/konomitv/config.yaml || install -m 0660 ${konomitvConfig} /var/lib/konomitv/config.yaml
        ${pkgs.local.konomitv.pythonEnv}/bin/python ${./configure-konomitv.py} /var/lib/konomitv/config.yaml ${toString keepAliveSeconds}
      '';
    };
  };

  services.nginx.virtualHosts.${tailnetHostname}.locations = {
    "= /tv".return = "308 ${tailnetOrigin}/tv/";
    "= /tv/sw.js" =
      (mkProxyLocation 7000 ''
        proxy_set_header If-Modified-Since "";
        proxy_set_header If-None-Match "";
        proxy_hide_header ETag;
        proxy_hide_header Last-Modified;
        add_header Cache-Control "no-cache" always;
      '')
      // {
        proxyPass = "http://127.0.0.1:7000/sw.js";
      };
    "^~ /tv/" = (mkProxyLocation 7000 "proxy_read_timeout 86400s;") // {
      proxyPass = "http://127.0.0.1:7000/";
    };
  };
}
