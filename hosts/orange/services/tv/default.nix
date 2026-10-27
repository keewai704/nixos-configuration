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
  televisionRoot = "${storageRoot}/KonomiTV";
  recordings = "${televisionRoot}/Recordings";
  captures = "${televisionRoot}/Captures";
  keepAliveSeconds = 120;
  queueRoot = "/var/lib/tv-recording/queue";
  recordingHook = pkgs.replaceVars ./PostRecEnd.lua {
    inherit recordings;
    queue = queueRoot;
  };
  disabledChannels = pkgs.writeText "tv-disabled-channels.json" (
    builtins.toJSON {
      networks = [
        32080
        32096
      ];
      services = [
        [
          32086
          32086
          43057
        ]
      ];
    }
  );
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
        Caption = 1;
        Data = 1;
      };
      REC_DEF = {
        RecMode = 1;
        ServiceMode = 49;
      };
      "BonDriver_coax.so" = {
        Count = 0;
        GetEpg = 0;
        EPGCount = 0;
      };
      "BonDriver_LinuxMirakc.so" = {
        Count = 1;
        GetEpg = 1;
        EPGCount = 1;
        Priority = 1;
      };
      TVTEST = {
        Num = 1;
        "0" = "BonDriver_LinuxMirakc.so";
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
        Caption = 1;
        Data = 1;
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
  bonDriverConfig = ini.generate "BonDriver_LinuxMirakc.so.ini" {
    GLOBAL = {
      SERVER_TYPE = "http";
      SERVER_HOST = "127.0.0.1";
      SERVER_PORT = 40772;
      PRIORITY = 100;
      DECODE_B25 = 0;
      SERVICE_SPLIT = 0;
    };
  };
  konomitvConfig = (pkgs.formats.yaml { }).generate "konomitv.yaml" {
    general = {
      backend = "EDCB";
      edcb_url = "tcp://127.0.0.1:4510/";
      always_receive_tv_from_mirakurun = true;
      mirakurun_url = "http://127.0.0.1:40772/";
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
  imports = [ ./mirakc.nix ];

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
            televisionRoot
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
        "mirakc.service"
        "coax-pcsc.service"
        "tv-storage-prepare.service"
        "tv-recording-encode.service"
      ];
      after = [
        "mirakc.service"
        "coax-pcsc.service"
        "tv-storage-prepare.service"
        "tv-recording-encode.service"
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
        ln -sfn ${pkgs.local.bondriver-linuxmirakc}/lib/BonDriver_LinuxMirakc.so /var/lib/edcb/lib/BonDriver_LinuxMirakc.so
        ln -sfn ${bonDriverConfig} /var/lib/edcb/lib/BonDriver_LinuxMirakc.so.ini
        ln -sfn ${recordingHook} /var/lib/edcb/PostRecEnd.lua
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
          test -z "$(find /var/lib/edcb/Setting -name 'BonDriver_LinuxMirakc*.ChSet4.txt' -size +0c -print -quit)"; then
          EpgDataCap_Bon -d BonDriver_LinuxMirakc.so -chscan
          test -s /var/lib/edcb/Setting/ChSet5.txt
          test -n "$(find /var/lib/edcb/Setting -name 'BonDriver_LinuxMirakc*.ChSet4.txt' -size +0c -print -quit)"
        fi
        ${pkgs.python3}/bin/python ${./configure-channels.py} /var/lib/edcb/Setting ${disabledChannels}
        if ! test -e /var/lib/edcb/.initial-epg-complete; then
          EpgDataCap_Bon -d BonDriver_LinuxMirakc.so -epgcap
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
        ReadWritePaths = [
          recordings
          queueRoot
        ];
        ExecStart = "${pkgs.local.edcb}/bin/EpgTimerSrv";
        TimeoutStopSec = "50s";
      };
    };

    tv-recording-encode = {
      description = "Verify and replace completed recording video with HEVC while preserving TS data";
      wantedBy = [ "multi-user.target" ];
      requires = [ "tv-storage-prepare.service" ];
      after = [ "tv-storage-prepare.service" ];
      environment = {
        LIBVA_DRIVER_NAME = "iHD";
        XDG_CACHE_HOME = "/var/cache/tv-recording";
      };
      preStart = ''
        install -d -m 0770 /var/lib/tv-recording/{queue,failed,completed}
      '';
      serviceConfig = serviceDefaults // {
        StateDirectory = "tv-recording";
        StateDirectoryMode = "0750";
        LogsDirectory = "tv-recording";
        CacheDirectory = "tv-recording";
        ReadWritePaths = [ recordings ];
        Nice = 10;
        IOSchedulingClass = "idle";
        CPUQuota = "200%";
        MemoryMax = "2G";
        ExecStart = lib.escapeShellArgs [
          "${pkgs.python3}/bin/python"
          "${./recording-encode.py}"
          "--queue"
          queueRoot
          "--recordings"
          recordings
          "--logs"
          "/var/log/tv-recording"
          "--tsreplace"
          "${pkgs.local.tsreplace}/bin/tsreplace"
          "--encoder"
          "${pkgs.local.konomitv.binaries}/QSVEncC/QSVEncC.elf"
          "--ffmpeg"
          "${pkgs.local.konomitv.binaries}/FFmpeg/ffmpeg.elf"
          "--ffprobe"
          "${pkgs.local.konomitv.binaries}/FFmpeg/ffprobe.elf"
        ];
        TimeoutStopSec = "30s";
      };
    };

    konomitv = {
      description = "KonomiTV television and recording frontend";
      wantedBy = [ "multi-user.target" ];
      requires = [
        "edcb.service"
        "mirakc.service"
        storageMountUnit
      ];
      after = [
        "edcb.service"
        "mirakc.service"
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
        ${pkgs.local.konomitv.pythonEnv}/bin/python ${./configure-konomitv.py} ${konomitvConfig} /var/lib/konomitv/config.yaml
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
