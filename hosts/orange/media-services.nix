{
  lib,
  pkgs,
  ...
}:

let
  storageRoot = "/srv/storage";
  storageMountUnit = "srv-storage.mount";
  immichMediaRoot = "${storageRoot}/Pictures";
  immichBackupRoot = "${immichMediaRoot}/backups";
  legacyVaultwardenRoot = "${storageRoot}/server/vaultwarden";
  vaultwardenBackupRoot = "${storageRoot}/server/backups/vaultwarden-nixos";
  tailnetHostname = "orange.tail1e65cd.ts.net";
  nginxPort = 8000;
  noVncViewerUrl = "https://${tailnetHostname}/browser/vnc.html?autoconnect=true&reconnect=true&reconnect_delay=1000&resize=scale&path=browser/websockify";
  postgresqlPackage = pkgs.postgresql_17;
  nginxProxyHeaders = ''
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $tailscale_client_ip;
    proxy_set_header X-Forwarded-For $tailscale_client_ip;
    proxy_set_header X-Forwarded-Proto https;
    proxy_set_header X-Forwarded-Host $host;
    proxy_set_header X-Forwarded-Server $hostname;
  '';

  importImmichDatabase = pkgs.writeShellApplication {
    name = "import-existing-immich-database";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.findutils
      pkgs.gzip
    ];
    text = ''
      immich_database="immich"

      schema_present="$(${pkgs.util-linux}/bin/runuser -u postgres -- \
        ${postgresqlPackage}/bin/psql \
          --dbname "$immich_database" \
          --tuples-only \
          --no-align \
          --command "SELECT to_regclass('public.kysely_migrations') IS NOT NULL;")"

      if [ "$schema_present" = "t" ]; then
        echo "Immich database already contains a schema; skipping the legacy import."
        exit 0
      fi

      immich_backup="$(
        find ${lib.escapeShellArg immichBackupRoot} \
          -maxdepth 1 \
          -type f \
          -name 'immich-db-backup-*.sql.gz' \
          -printf '%T@ %p\n' \
          | sort --numeric-sort --reverse \
          | head --lines 1 \
          | cut --delimiter ' ' --fields 2-
      )"

      if [ -z "$immich_backup" ]; then
        echo "No existing Immich database backup was found in ${immichBackupRoot}." >&2
        exit 1
      fi

      echo "Importing the existing Immich database from $immich_backup"
      gzip --test "$immich_backup"
      gzip --decompress --stdout "$immich_backup" \
        | ${pkgs.util-linux}/bin/runuser -u postgres -- \
          ${postgresqlPackage}/bin/psql \
            --dbname "$immich_database" \
            --single-transaction \
            --set ON_ERROR_STOP=on

      ${pkgs.util-linux}/bin/runuser -u postgres -- \
        ${postgresqlPackage}/bin/psql \
          --dbname "$immich_database" \
          --command "ANALYZE;"
    '';
  };

  importVaultwardenData = pkgs.writeShellApplication {
    name = "import-existing-vaultwarden-data";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.sqlite
    ];
    text = ''
      vaultwarden_target="/var/lib/vaultwarden"
      legacy_database=${lib.escapeShellArg "${legacyVaultwardenRoot}/db.sqlite3"}

      if [ -s "$vaultwarden_target/db.sqlite3" ]; then
        echo "Vaultwarden database already exists on the SSD; skipping the legacy import."
        exit 0
      fi

      if [ ! -s "$legacy_database" ]; then
        echo "No existing Vaultwarden database was found at $legacy_database." >&2
        exit 1
      fi

      install --directory --mode 0700 --owner vaultwarden --group vaultwarden "$vaultwarden_target"
      rm --force "$vaultwarden_target/db.sqlite3.importing"
      sqlite3 "file:$legacy_database?immutable=1" \
        ".backup '$vaultwarden_target/db.sqlite3.importing'"

      integrity_result="$(sqlite3 "$vaultwarden_target/db.sqlite3.importing" 'PRAGMA integrity_check;')"
      if [ "$integrity_result" != "ok" ]; then
        echo "Imported Vaultwarden database failed its integrity check: $integrity_result" >&2
        exit 1
      fi

      mv "$vaultwarden_target/db.sqlite3.importing" "$vaultwarden_target/db.sqlite3"

      for item_name in rsa_key.pem rsa_key.der rsa_key.pub.der attachments sends; do
        source_path=${lib.escapeShellArg legacyVaultwardenRoot}/"$item_name"
        if [ -e "$source_path" ]; then
          cp --archive "$source_path" "$vaultwarden_target/"
        fi
      done

      chown --recursive vaultwarden:vaultwarden "$vaultwarden_target"
      chmod 0600 "$vaultwarden_target/db.sqlite3"
      echo "Imported the existing Vaultwarden data onto the SSD."
    '';
  };
in
{
  # This disk already contains the previous Immich and Vaultwarden data. It is
  # intentionally mounted without formatting or repartitioning.
  fileSystems.${storageRoot} = {
    device = "/dev/disk/by-uuid/8d14b091-590e-414a-aa82-dd0670742792";
    fsType = "ext4";
    options = [
      "noatime"
      "nodev"
      "nosuid"
    ];
  };

  # Publish the HDD on the trusted LAN and tailnet only. NetBIOS discovery is
  # useful on the LAN; tailnet clients connect directly over modern SMB/445.
  networking.firewall.interfaces = {
    enp2s0 = {
      allowedTCPPorts = [
        139
        445
      ];
      allowedUDPPorts = [
        137
        138
      ];
    };
    tailscale0.allowedTCPPorts = [ 445 ];
  };

  users = {
    groups.immich-media.gid = 1000;
    users = {
      immich.extraGroups = [
        "render"
        "video"
      ];
      keewai.extraGroups = [ "immich-media" ];
    };
  };

  hardware.graphics = {
    enable = true;
    extraPackages = [
      pkgs.intel-media-driver
      pkgs.vpl-gpu-rt
    ];
  };

  services = {
    samba = {
      enable = true;
      winbindd.enable = false;
      settings = {
        global = {
          "map to guest" = "Bad User";
        };

        storage = {
          path = storageRoot;
          comment = "Orange HDD storage";
          "guest ok" = "yes";
          "guest only" = "yes";
          "read only" = "no";
          "force user" = "keewai";
          "force group" = "immich-media";
          "create mask" = "0664";
          "directory mask" = "0775";
          "veto files" = "/server/lost+found/";
        };
      };
    };

    immich = {
      enable = true;
      host = "127.0.0.1";
      port = 2283;
      mediaLocation = immichMediaRoot;
      group = "immich-media";

      # Disable both the NixOS ML worker and every ML feature in Immich itself.
      machine-learning.enable = false;
      environment = {
        IMMICH_MACHINE_LEARNING_ENABLED = "false";
        LIBVA_DRIVER_NAME = "iHD";
      };

      # The Alder Lake-N iGPU handles only on-demand playback transcoding.
      accelerationDevices = [ "/dev/dri/renderD128" ];
      settings = {
        backup.database = {
          enabled = true;
          cronExpression = "0 2 * * *";
          keepLastAmount = 14;
        };
        ffmpeg = {
          accel = "qsv";
          accelDecode = true;
          transcode = "disabled";
          realtime.enabled = true;
        };
        machineLearning = {
          enabled = false;
          availabilityChecks.enabled = false;
          clip.enabled = false;
          duplicateDetection.enabled = false;
          facialRecognition.enabled = false;
          ocr.enabled = false;
        };
        nightlyTasks.clusterNewFaces = false;
        server.externalDomain = "https://${tailnetHostname}";
      };
    };

    # Pin the database major version so an ordinary flake update cannot perform
    # an implicit PostgreSQL major upgrade on the SSD.
    postgresql.package = postgresqlPackage;

    vaultwarden = {
      enable = true;
      dbBackend = "sqlite";
      backupDir = vaultwardenBackupRoot;
      config = {
        DOMAIN = "https://${tailnetHostname}/vault";
        EXPERIMENTAL_CLIENT_FEATURE_FLAGS = "cxp-import-mobile";
        ROCKET_ADDRESS = "127.0.0.1";
        ROCKET_PORT = 8222;
        SIGNUPS_ALLOWED = false;
      };
    };

    nginx = {
      enable = true;
      recommendedOptimisation = true;
      recommendedProxySettings = true;
      proxyTimeout = "600s";
      clientMaxBodySize = "50000M";
      appendHttpConfig = ''
        # Tailscale Serve supplies the original tailnet client in this header.
        # Fall back to the direct peer for loopback health checks.
        map $http_x_forwarded_for $tailscale_client_ip {
          default $http_x_forwarded_for;
          "" $remote_addr;
        }

      '';

      virtualHosts.${tailnetHostname} = {
        default = true;
        listen = [
          {
            addr = "127.0.0.1";
            port = nginxPort;
          }
        ];
        extraConfig = ''
          client_body_buffer_size 1024k;
          send_timeout 600s;
        '';
        locations = {
          # Redirect to the canonical HTTPS origin explicitly. Since nginx
          # listens on loopback HTTP, a relative return would otherwise expose
          # its internal :8000 address in the generated Location header.
          "= /browser".return = "302 ${noVncViewerUrl}";
          "= /browser/".return = "302 ${noVncViewerUrl}";

          "^~ /browser/" = {
            # The trailing slash strips /browser/ before forwarding to
            # websockify's root-mounted noVNC web application.
            proxyPass = "http://127.0.0.1:6080/";
            proxyWebsockets = true;
            recommendedProxySettings = false;
            extraConfig = ''
              proxy_buffering off;
              access_log off;
              proxy_read_timeout 86400s;
              proxy_send_timeout 86400s;
              proxy_set_header Host 127.0.0.1:6080;
              proxy_set_header X-Real-IP $tailscale_client_ip;
              proxy_set_header X-Forwarded-For $tailscale_client_ip;
              proxy_set_header X-Forwarded-Proto https;
              proxy_set_header X-Forwarded-Host $host;
              proxy_set_header X-Forwarded-Prefix /browser;
              proxy_set_header X-Forwarded-Server $hostname;
            '';
          };

          "= /vault".return = "308 https://${tailnetHostname}/vault/";

          "^~ /vault/" = {
            proxyPass = "http://127.0.0.1:8222";
            proxyWebsockets = true;
            recommendedProxySettings = false;
            extraConfig = ''
              proxy_buffering off;
              ${nginxProxyHeaders}
            '';
          };

          "/" = {
            proxyPass = "http://127.0.0.1:2283";
            proxyWebsockets = true;
            recommendedProxySettings = false;
            extraConfig = ''
              proxy_request_buffering off;
              proxy_buffering off;
              ${nginxProxyHeaders}
            '';
          };
        };
      };
    };
  };

  systemd = {
    tmpfiles = {
      rules = [
        "d /var/lib/vaultwarden 0700 vaultwarden vaultwarden -"
        "z ${storageRoot} 0775 keewai immich-media -"
      ];

      # Override Immich's default 0700 mount-root rule. Existing files below
      # this directory already use gid 1000 and remain otherwise untouched.
      settings.immich.${immichMediaRoot}.e = {
        user = lib.mkForce "keewai";
        group = lib.mkForce "immich-media";
        mode = lib.mkForce "0770";
      };
    };

    services = {
      samba-smbd = {
        requires = [ storageMountUnit ];
        after = [ storageMountUnit ];
      };

      media-storage-prepare = {
        description = "Prepare mounted HDD directories for media services";
        requires = [ storageMountUnit ];
        after = [ storageMountUnit ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          ${pkgs.coreutils}/bin/install \
            --directory \
            --mode 0770 \
            --owner keewai \
            --group immich-media \
            ${lib.escapeShellArg immichMediaRoot}

          ${pkgs.coreutils}/bin/install \
            --directory \
            --mode 0770 \
            --owner vaultwarden \
            --group vaultwarden \
            ${lib.escapeShellArg vaultwardenBackupRoot}
        '';
      };

      immich-import-existing-database = {
        description = "Import the existing Immich PostgreSQL backup once";
        requires = [
          "media-storage-prepare.service"
          storageMountUnit
          "postgresql-setup.service"
        ];
        after = [
          "media-storage-prepare.service"
          storageMountUnit
          "postgresql-setup.service"
        ];
        before = [ "immich-server.service" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = lib.getExe importImmichDatabase;
        };
      };

      immich-server = {
        requires = [
          "media-storage-prepare.service"
          storageMountUnit
          "immich-import-existing-database.service"
        ];
        after = [
          "media-storage-prepare.service"
          storageMountUnit
          "immich-import-existing-database.service"
        ];
        serviceConfig.ReadWritePaths = [ immichMediaRoot ];
      };

      vaultwarden-import-existing = {
        description = "Import the existing Vaultwarden state once";
        requires = [
          "media-storage-prepare.service"
          storageMountUnit
        ];
        after = [
          "media-storage-prepare.service"
          storageMountUnit
        ];
        before = [
          "backup-vaultwarden.service"
          "vaultwarden.service"
        ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = lib.getExe importVaultwardenData;
        };
      };

      vaultwarden = {
        requires = [
          storageMountUnit
          "vaultwarden-import-existing.service"
        ];
        after = [
          storageMountUnit
          "vaultwarden-import-existing.service"
        ];
      };

      backup-vaultwarden = {
        requires = [
          "media-storage-prepare.service"
          storageMountUnit
          "vaultwarden-import-existing.service"
        ];
        after = [
          "media-storage-prepare.service"
          storageMountUnit
          "vaultwarden-import-existing.service"
        ];
      };

      tailscale-serve-nginx = {
        description = "Publish local services with Tailscale Serve";
        requires = [
          "nginx.service"
          "tailscaled.service"
        ];
        wants = [ "network-online.target" ];
        after = [
          "network-online.target"
          "nginx.service"
          "tailscaled.service"
        ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          Restart = "on-failure";
          RestartSec = "5s";
          # Remove persisted imperative mappings first, so old non-443
          # listeners cannot survive a configuration change.
          ExecStartPre = "${pkgs.tailscale}/bin/tailscale serve reset";
          ExecStart = "${pkgs.tailscale}/bin/tailscale serve --bg --yes --https=443 http://127.0.0.1:${toString nginxPort}";
        };
      };
    };

    timers.backup-vaultwarden.timerConfig.OnCalendar = lib.mkForce "*-*-* 03:30:00";
  };
}
