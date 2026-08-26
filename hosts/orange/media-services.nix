{
  hermesAgentPackage,
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
  hermesOneNginxPort = 8001;
  hermexNginxPort = 8002;
  hermesDashboardPort = 9119;
  hermesApiPort = 8642;
  hermexWebUiPort = 8787;
  hermesDashboardOrigin = "http://127.0.0.1:${toString hermesDashboardPort}";
  hermesApiOrigin = "http://127.0.0.1:${toString hermesApiPort}";
  hermexWebUiOrigin = "http://127.0.0.1:${toString hermexWebUiPort}";
  hermesHome = "/home/keewai/.hermes";
  hermesSecretsFile = "${hermesHome}/secrets.env";
  hermesWebUiEnvironmentFile = "/run/hermes-webui/webui.env";
  postgresqlPackage = pkgs.postgresql_17;
  nginxProxyHeaders = ''
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $tailscale_client_ip;
    proxy_set_header X-Forwarded-For $tailscale_client_ip;
    proxy_set_header X-Forwarded-Proto https;
    proxy_set_header X-Forwarded-Host $host;
    proxy_set_header X-Forwarded-Server $hostname;
  '';
  hermesOneProxyHeaders = upstreamPort: ''
    proxy_set_header Host 127.0.0.1:${toString upstreamPort};
    proxy_set_header X-Real-IP $tailscale_client_ip;
    proxy_set_header X-Forwarded-For $tailscale_client_ip;
    proxy_set_header X-Forwarded-Proto https;
    proxy_set_header X-Forwarded-Host 127.0.0.1:${toString upstreamPort};
    proxy_set_header X-Forwarded-Server $hostname;
  '';
  hermexProxyHeaders = ''
    proxy_set_header Host ${tailnetHostname}:8444;
    proxy_set_header X-Real-IP $tailscale_client_ip;
    proxy_set_header X-Forwarded-For $tailscale_client_ip;
    proxy_set_header X-Forwarded-Proto https;
    proxy_set_header X-Forwarded-Host ${tailnetHostname}:8444;
    proxy_set_header X-Forwarded-Port 8444;
    proxy_set_header X-Forwarded-Server $hostname;
  '';

  # Hermex authenticates against Hermes WebUI, not the Hermes Agent dashboard
  # or its OpenAI-compatible API. Derive the WebUI password at service start so
  # the secret remains outside both the repository and the Nix store.
  prepareHermesWebUiEnvironment = pkgs.writeShellApplication {
    name = "prepare-hermes-webui-environment";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnused
    ];
    text = ''
      secrets_file=${lib.escapeShellArg hermesSecretsFile}
      runtime_file=${lib.escapeShellArg hermesWebUiEnvironmentFile}

      if [ ! -r "$secrets_file" ]; then
        echo "Hermex cannot read $secrets_file" >&2
        exit 1
      fi

      password="$(sed -n 's/^API_SERVER_KEY=//p' "$secrets_file")"
      if [ -z "$password" ]; then
        echo "API_SERVER_KEY is missing from $secrets_file" >&2
        exit 1
      fi

      # Keep the generated EnvironmentFile deliberately simple. The generated
      # Hermes key is URL-safe, so reject an accidental manual replacement
      # rather than relying on systemd quoting rules for a secret value.
      case "$password" in
        *[!A-Za-z0-9._~-]*)
          echo "API_SERVER_KEY contains characters unsafe for an env file" >&2
          exit 1
          ;;
      esac

      umask 077
      trap 'rm -f "$runtime_file.tmp"' EXIT
      sed \
        -e '/^HERMES_WEBUI_PASSWORD=/d' \
        -e '/^HERMES_WEBUI_GATEWAY_API_KEY=/d' \
        "$secrets_file" > "$runtime_file.tmp"
      printf '\nHERMES_WEBUI_PASSWORD=%s\n' "$password" >> "$runtime_file.tmp"
      printf 'HERMES_WEBUI_GATEWAY_API_KEY=%s\n' "$password" >> "$runtime_file.tmp"
      mv "$runtime_file.tmp" "$runtime_file"
      trap - EXIT
    '';
  };

  importImmichDatabase = pkgs.writeShellApplication {
    name = "import-existing-immich-database";
    runtimeInputs = [
      postgresqlPackage
      pkgs.coreutils
      pkgs.findutils
      pkgs.gzip
      pkgs.util-linux
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
      openFirewall = false;
      winbindd.enable = false;
      settings = {
        global = {
          "map to guest" = "Bad User";
          "server role" = "standalone server";
        };

        storage = {
          path = storageRoot;
          comment = "Orange HDD storage";
          browseable = "yes";
          "guest ok" = "yes";
          "guest only" = "yes";
          "read only" = "no";
          "force user" = "keewai";
          "force group" = "immich-media";
          "create mask" = "0664";
          "directory mask" = "0775";
          "veto files" = "/server/lost+found/";
          "delete veto files" = "no";
        };
      };
    };

    immich = {
      enable = true;
      host = "127.0.0.1";
      port = 2283;
      openFirewall = false;
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
        ENABLE_WEBSOCKET = true;
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

        # Browser WebSockets carry the public Origin, while Hermes validates
        # Host and Origin against its loopback bind. Accept only the expected
        # tailnet origin and translate it to the protected upstream origin.
        map $http_origin $hermes_origin_allowed {
          default 0;
          "" 1;
          "https://${tailnetHostname}" 1;
        }
        map $http_origin $hermes_upstream_origin {
          default "";
          "" "";
          "https://${tailnetHostname}" "${hermesDashboardOrigin}";
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
          "= /hermes".return = "308 https://${tailnetHostname}/hermes/";

          "^~ /hermes/" = {
            # The trailing slash strips /hermes/ before forwarding. Hermes
            # reconstructs its public paths from X-Forwarded-Prefix.
            proxyPass = "${hermesDashboardOrigin}/";
            proxyWebsockets = true;
            recommendedProxySettings = false;
            extraConfig = ''
              if ($hermes_origin_allowed = 0) { return 403; }

              proxy_request_buffering off;
              proxy_buffering off;
              access_log off;
              error_log stderr crit;
              proxy_read_timeout 86400s;
              proxy_send_timeout 86400s;
              proxy_set_header Host 127.0.0.1:${toString hermesDashboardPort};
              proxy_set_header Origin $hermes_upstream_origin;
              proxy_set_header X-Real-IP $tailscale_client_ip;
              proxy_set_header X-Forwarded-For $tailscale_client_ip;
              proxy_set_header X-Forwarded-Proto https;
              proxy_set_header X-Forwarded-Host $host;
              proxy_set_header X-Forwarded-Prefix /hermes;
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

      # Hermes One currently anchors dashboard discovery and WebSocket URLs
      # at the URL origin, so a /hermes path prefix cannot provide its full
      # remote transport. Give it a dedicated HTTPS endpoint (published by
      # Tailscale Serve on :8443) where /api belongs to the dashboard and /v1
      # plus /health belong to the OpenAI-compatible API server. Keeping this
      # on a separate local nginx port avoids taking Immich's root /api paths.
      virtualHosts.hermes-one = {
        serverName = tailnetHostname;
        listen = [
          {
            addr = "127.0.0.1";
            port = hermesOneNginxPort;
          }
        ];
        extraConfig = ''
          client_body_buffer_size 1024k;
          send_timeout 600s;
          # Hermes WebSockets carry the session token in the query string.
          # Disable this dedicated endpoint's access log so it is never
          # persisted as part of nginx's standard $request field.
          access_log off;
          error_log stderr crit;
        '';
        locations = {
          "^~ /api/" = {
            proxyPass = hermesDashboardOrigin;
            proxyWebsockets = true;
            recommendedProxySettings = false;
            extraConfig = ''
              proxy_request_buffering off;
              proxy_buffering off;
              proxy_read_timeout 86400s;
              proxy_send_timeout 86400s;
              ${hermesOneProxyHeaders hermesDashboardPort}
              proxy_set_header Origin "";
            '';
          };

          "^~ /v1/" = {
            proxyPass = hermesApiOrigin;
            recommendedProxySettings = false;
            extraConfig = ''
              proxy_request_buffering off;
              proxy_buffering off;
              proxy_read_timeout 86400s;
              proxy_send_timeout 86400s;
              ${hermesOneProxyHeaders hermesApiPort}
            '';
          };

          "= /health" = {
            proxyPass = "${hermesApiOrigin}/health";
            recommendedProxySettings = false;
            extraConfig = ''
              ${hermesOneProxyHeaders hermesApiPort}
            '';
          };

          "/" = {
            proxyPass = hermesDashboardOrigin;
            proxyWebsockets = true;
            recommendedProxySettings = false;
            extraConfig = ''
              proxy_request_buffering off;
              proxy_buffering off;
              proxy_read_timeout 86400s;
              proxy_send_timeout 86400s;
              ${hermesOneProxyHeaders hermesDashboardPort}
              proxy_set_header Origin "";
            '';
          };
        };
      };

      # Hermex is a native client for nesquena/hermes-webui, not for the
      # Hermes dashboard used by Hermes One. Publish the WebUI at its own URL
      # origin because Hermex probes /health and uses root-relative API paths.
      virtualHosts.hermex = {
        serverName = tailnetHostname;
        listen = [
          {
            addr = "127.0.0.1";
            port = hermexNginxPort;
          }
        ];
        extraConfig = ''
          client_max_body_size 20m;
          client_body_buffer_size 1024k;
          send_timeout 86400s;
          access_log off;
        '';
        locations."/" = {
          proxyPass = hermexWebUiOrigin;
          proxyWebsockets = true;
          recommendedProxySettings = false;
          extraConfig = ''
            proxy_request_buffering off;
            proxy_buffering off;
            proxy_read_timeout 86400s;
            proxy_send_timeout 86400s;
            ${hermexProxyHeaders}
          '';
        };
      };
    };
  };

  # Run Hermes WebUI directly from its pinned Nix package. It uses the same
  # host user and Hermes state as the official Home Manager service, so no
  # container path translation or writable application/venv staging is needed.
  services.hermes-webui = {
    enable = true;
    user = "keewai";
    group = "users";
    host = "127.0.0.1";
    port = hermexWebUiPort;
    stateDir = "${hermesHome}/webui";
    hermesHome = hermesHome;
    agent.package = hermesAgentPackage;
    environmentFiles = [ hermesWebUiEnvironmentFile ];
    extraEnvironment = {
      HOME = "/home/keewai";
      HERMES_WEBUI_DEFAULT_WORKSPACE = "/home/keewai";
      HERMES_API_URL = "http://127.0.0.1:8642";
      CAMOFOX_URL = "http://127.0.0.1:9377";

      # Existing Home Manager-managed credentials must not be chmod'ed by the
      # WebUI. TLS terminates at the trusted nginx/Tailscale proxy.
      HERMES_SKIP_CHMOD = "1";
      HERMES_WEBUI_SECURE = "1";
      HERMES_WEBUI_ALLOWED_ORIGINS = "https://orange.tail1e65cd.ts.net:8444";
      HERMES_WEBUI_TRUST_FORWARDED_HOST = "1";
      HERMES_WEBUI_TRUST_FORWARDED_FOR = "1";
      HERMES_WEBUI_TRUST_FORWARDED_PROTO = "1";
    };
  };

  systemd = {
    tmpfiles = {
      rules = [
        "d /var/lib/vaultwarden 0700 vaultwarden vaultwarden -"
        "d /run/hermes-webui 0700 keewai users -"
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
      # EnvironmentFile is loaded before a unit's ExecStartPre commands. Build
      # the derived password file in a separate prerequisite unit so it exists
      # before systemd starts preparing the WebUI process environment.
      hermes-webui-environment = {
        description = "Prepare the private Hermes WebUI environment";
        before = [ "hermes-webui.service" ];
        requiredBy = [ "hermes-webui.service" ];
        serviceConfig = {
          Type = "oneshot";
          User = "keewai";
          Group = "users";
          UMask = "0077";
          ExecStart = lib.getExe prepareHermesWebUiEnvironment;
        };
      };

      samba-smbd = {
        requires = [ storageMountUnit ];
        after = [ storageMountUnit ];
      };

      media-storage-prepare = {
        description = "Prepare mounted HDD directories for media services";
        requires = [ storageMountUnit ];
        after = [ storageMountUnit ];
        before = [
          "backup-vaultwarden.service"
          "immich-import-existing-database.service"
          "immich-server.service"
          "vaultwarden-import-existing.service"
        ];
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
        description = "Publish the local nginx proxy with Tailscale Serve";
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
          ExecStart = [
            "${pkgs.tailscale}/bin/tailscale serve --bg --yes --https=443 http://127.0.0.1:${toString nginxPort}"
            "${pkgs.tailscale}/bin/tailscale serve --bg --yes --https=8443 http://127.0.0.1:${toString hermesOneNginxPort}"
            "${pkgs.tailscale}/bin/tailscale serve --bg --yes --https=8444 http://127.0.0.1:${toString hermexNginxPort}"
          ];
        };
      };
    };

    timers.backup-vaultwarden.timerConfig.OnCalendar = lib.mkForce "*-*-* 03:30:00";
  };
}
