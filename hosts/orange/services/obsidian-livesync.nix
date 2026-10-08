{ lib, pkgs, ... }:
let
  inherit (import ../settings.nix)
    couchdbPort
    obsidianVault
    tailnetHostname
    tailnetOrigin
    ;
  secretsDir = "/var/lib/obsidian-livesync-secrets";
  passwordFile = "${secretsDir}/couchdb-password";
  adminUser = "obsidian";
  database = "obsidian";
  couchdbUrl = "http://127.0.0.1:${toString couchdbPort}";
  livesync-bridge = pkgs.callPackage ../../../pkgs/livesync-bridge { };
  bridgeConfig = pkgs.writeText "livesync-bridge.json" (
    builtins.toJSON {
      peers = [
        {
          type = "couchdb";
          name = "couchdb";
          group = "vault";
          inherit database;
          username = adminUser;
          password = "@password@";
          url = couchdbUrl;
          passphrase = "";
          obfuscatePassphrase = "";
          baseDir = "";
          useRemoteTweaks = true;
        }
        {
          type = "storage";
          name = "vault";
          group = "vault";
          baseDir = "${obsidianVault}/";
          scanOfflineChanges = true;
        }
      ];
    }
  );
in
{
  services.couchdb = {
    enable = true;
    bindAddress = "127.0.0.1";
    port = couchdbPort;
    extraConfigFiles = [ "/var/lib/couchdb/admins.ini" ];
    extraConfig = {
      couchdb = {
        single_node = true;
        max_document_size = 50000000;
      };
      chttpd = {
        require_valid_user = true;
        max_http_request_size = 4294967296;
        enable_cors = true;
      };
      chttpd_auth = {
        require_valid_user = true;
        authentication_redirect = "/_utils/session.html";
      };
      httpd = {
        WWW-Authenticate = ''Basic realm="couchdb"'';
        enable_cors = true;
      };
      cors = {
        origins = "app://obsidian.md,capacitor://localhost,http://localhost";
        credentials = true;
        headers = "accept, authorization, content-type, origin, referer";
        methods = "GET, PUT, POST, HEAD, DELETE";
        max_age = 3600;
      };
    };
  };

  systemd = {
    tmpfiles.rules = [ "d ${obsidianVault} 0700 keewai users -" ];

    services = {
      obsidian-livesync-secrets = {
        description = "Generate the Obsidian LiveSync CouchDB password";
        before = [ "couchdb.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          StateDirectory = baseNameOf secretsDir;
          StateDirectoryMode = "0700";
          UMask = "0077";
        };
        script = ''
          if [ ! -s ${passwordFile} ]; then
            ${pkgs.openssl}/bin/openssl rand -hex 24 > ${passwordFile}.tmp
            mv ${passwordFile}.tmp ${passwordFile}
          fi
        '';
      };

      couchdb = {
        requires = [ "obsidian-livesync-secrets.service" ];
        after = [ "obsidian-livesync-secrets.service" ];
        preStart = lib.mkAfter ''
          umask 077
          printf '[admins]\n${adminUser} = %s\n' "$(cat "$CREDENTIALS_DIRECTORY/password")" > /var/lib/couchdb/admins.ini
        '';
        environment.ERL_EPMD_ADDRESS = "127.0.0.1";
        serviceConfig.LoadCredential = "password:${passwordFile}";
      };

      livesync-bridge = {
        description = "Sync the Obsidian LiveSync database with the server vault";
        requires = [ "couchdb.service" ];
        after = [ "couchdb.service" ];
        wantedBy = [ "multi-user.target" ];
        path = [
          pkgs.curl
          pkgs.gnused
        ];
        environment = {
          DENO_DIR = "%S/livesync-bridge/deno";
          LSB_CONFIG = "%t/livesync-bridge/config.json";
          LSB_HEALTH_FILE = "%t/livesync-bridge/health.json";
        };
        preStart = ''
          password=$(cat "$CREDENTIALS_DIRECTORY/password")
          sed "s|@password@|$password|" ${bridgeConfig} > "$RUNTIME_DIRECTORY/config.json"
          curl -sS --retry 30 --retry-all-errors --retry-delay 2 -o /dev/null -u "${adminUser}:$password" ${couchdbUrl}/_up
          status=$(curl -sS -o /dev/null -w '%{http_code}' -u "${adminUser}:$password" -X PUT ${couchdbUrl}/${database})
          case "$status" in
            201 | 202 | 412) ;;
            *) echo "Could not create CouchDB database ${database}: HTTP $status" >&2; exit 1 ;;
          esac
        '';
        serviceConfig = {
          ExecStart = lib.getExe livesync-bridge;
          User = "keewai";
          Group = "users";
          UMask = "0077";
          LoadCredential = "password:${passwordFile}";
          StateDirectory = "livesync-bridge";
          RuntimeDirectory = "livesync-bridge";
          WorkingDirectory = "%S/livesync-bridge";
          Restart = "always";
          RestartSec = 10;
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = "tmpfs";
          BindPaths = [ obsidianVault ];
        };
      };
    };
  };

  services.nginx.virtualHosts.${tailnetHostname}.locations = {
    "= /couchdb".return = "308 ${tailnetOrigin}/couchdb/";
    "^~ /couchdb/" = {
      proxyPass = "${couchdbUrl}/";
      recommendedProxySettings = false;
      extraConfig = ''
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $tailscale_client_ip;
        proxy_set_header X-Forwarded-For $tailscale_client_ip;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Server $hostname;
      '';
    };
  };
}
