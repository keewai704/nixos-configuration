{ lib, pkgs, ... }:
let
  inherit (import ./settings.nix)
    edcbPort
    mirakcPort
    recordings
    queueRoot
    tvEnvironment
    serviceDefaults
    tuners
    ;
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
  tunerCount = builtins.length tuners;
  nativeChannels = pkgs.writeText "torne-channels.tsv" (
    lib.concatMapStringsSep "\n" (
      channel: "${channel.channel}\t${lib.removePrefix "--tsid " channel.extra-args}\t${channel.name}"
    ) (import ./channels.nix)
    + "\n"
  );
  nativeBonDrivers = pkgs.runCommand "torne-bondrivers" { nativeBuildInputs = [ pkgs.patchelf ]; } (
    lib.concatMapStringsSep "\n" (
      tuner:
      let
        name = "BonDriver_Torne${tuner.id}.so";
        settings = ini.generate "${name}.ini" {
          Torne = {
            Socket = "/run/torne-${tuner.id}/control.sock";
            Name = "Sony CECH-ZD1 J ${tuner.id}";
            Channels = nativeChannels;
          };
        };
      in
      ''
        install -Dm755 ${pkgs.local.torne-receiver}/lib/BonDriver_Torne.so $out/${name}
        patchelf --set-soname ${name} $out/${name}
        ln -s ${settings} $out/${name}.ini
      ''
    ) tuners
  );
  edcbSettings = {
    "Common.ini" = ini.generate "Common.ini" {
      SET = {
        DataSavePath = "/var/lib/edcb/Setting";
        RecFolderNum = 1;
        RecFolderPath0 = recordings;
        RecExePath = "${pkgs.local.edcb}/bin/EpgDataCap_Bon";
      };
    };
    "EpgTimerSrv.ini" = ini.generate "EpgTimerSrv.ini" (
      {
        SET = {
          EnableTCPSrv = 1;
          TCPPort = edcbPort;
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
          Count = tunerCount;
          GetEpg = 1;
          EPGCount = tunerCount;
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
      }
      // lib.listToAttrs (
        map (tuner: {
          name = "BonDriver_Torne${tuner.id}.so";
          value = {
            Count = 0;
            GetEpg = 0;
            EPGCount = 0;
          };
        }) tuners
      )
    );
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
      SERVER_PORT = mirakcPort;
      PRIORITY = 100;
      DECODE_B25 = 0;
      SERVICE_SPLIT = 0;
    };
  };
in
{
  orange.healthMonitor = {
    units = [ "edcb.service" ];
    loopbackPorts = [ edcbPort ];
  };

  systemd.services = {
    edcb-setup = {
      description = "Prepare native EDCB and scan the terrestrial tuner on first start";
      requires = [
        "mirakc.service"
        "pcscd.service"
        "tv-storage-prepare.service"
        "tv-recording-encode.service"
      ];
      after = [
        "mirakc.service"
        "pcscd.service"
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
        for driver in ${nativeBonDrivers}/*; do
          ln -sfn "$driver" "/var/lib/edcb/lib/$(basename "$driver")"
        done
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
                with socket.create_connection(('127.0.0.1', ${toString edcbPort}), timeout=1):
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
  };
}
