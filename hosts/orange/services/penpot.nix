{ lib, pkgs, ... }:

let
  inherit (import ../settings.nix) penpotPort tailnetOrigin;
  penpotVersion = "2.18.2";
  stateRoot = "/var/lib/penpot";
  assetsRoot = "${stateRoot}/assets";
  postgresRoot = "${stateRoot}/postgres";
  secretsFile = "${stateRoot}/secrets.env";
  networkName = "penpot";

  flags = lib.concatStringsSep " " [
    "disable-registration"
    "enable-login-with-password"
    "disable-email-verification"
    "disable-smtp"
    "enable-prepl-server"
    "enable-mcp"
  ];

  commonEnvironment = {
    PENPOT_FLAGS = flags;
    PENPOT_PUBLIC_URI = "${tailnetOrigin}/penpot";
  };

  bodySizeEnvironment = {
    PENPOT_HTTP_SERVER_MAX_BODY_SIZE = "367001600";
    PENPOT_HTTP_SERVER_MAX_MULTIPART_BODY_SIZE = "367001600";
  };

  generateSecrets = pkgs.writeShellApplication {
    name = "penpot-generate-secrets";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.openssl
    ];
    text = ''
      if [ -s ${secretsFile} ]; then
        exit 0
      fi
      umask 0077
      databasePassword=$(openssl rand -hex 32)
      {
        echo "PENPOT_SECRET_KEY=$(openssl rand -hex 64)"
        echo "PENPOT_DATABASE_PASSWORD=$databasePassword"
        echo "POSTGRES_PASSWORD=$databasePassword"
      } > ${secretsFile}.tmp
      mv ${secretsFile}.tmp ${secretsFile}
    '';
  };

  podmanDependencies = [
    "penpot-network.service"
    "penpot-secrets.service"
  ];

  mkContainer =
    attrs:
    lib.recursiveUpdate {
      networks = [ networkName ];
      environmentFiles = [ secretsFile ];
    } attrs;
in
{
  virtualisation = {
    podman.enable = true;
    oci-containers = {
      backend = "podman";
      containers = {
        penpot-postgres = mkContainer {
          image = "docker.io/library/postgres:17";
          volumes = [ "${postgresRoot}:/var/lib/postgresql/data" ];
          environment = {
            POSTGRES_DB = "penpot";
            POSTGRES_USER = "penpot";
            POSTGRES_INITDB_ARGS = "--data-checksums";
          };
          extraOptions = [ "--stop-signal=SIGINT" ];
        };

        penpot-valkey = mkContainer {
          image = "docker.io/valkey/valkey:8.1";
          environment.VALKEY_EXTRA_FLAGS = "--maxmemory 128mb --maxmemory-policy volatile-lfu";
        };

        penpot-backend = mkContainer {
          image = "docker.io/penpotapp/backend:${penpotVersion}";
          dependsOn = [
            "penpot-postgres"
            "penpot-valkey"
          ];
          volumes = [ "${assetsRoot}:/opt/data/assets" ];
          environment =
            commonEnvironment
            // bodySizeEnvironment
            // {
              PENPOT_DATABASE_URI = "postgresql://penpot-postgres/penpot";
              PENPOT_DATABASE_USERNAME = "penpot";
              PENPOT_REDIS_URI = "redis://penpot-valkey/0";
              PENPOT_OBJECTS_STORAGE_BACKEND = "fs";
              PENPOT_OBJECTS_STORAGE_FS_DIRECTORY = "/opt/data/assets";
              PENPOT_TELEMETRY_ENABLED = "false";
            };
        };

        penpot-exporter = mkContainer {
          image = "docker.io/penpotapp/exporter:${penpotVersion}";
          dependsOn = [
            "penpot-backend"
            "penpot-valkey"
          ];
          environment = commonEnvironment // {
            PENPOT_INTERNAL_URI = "http://penpot-frontend:8080";
            PENPOT_REDIS_URI = "redis://penpot-valkey/0";
          };
        };

        penpot-mcp = mkContainer {
          image = "docker.io/penpotapp/mcp:${penpotVersion}";
          environmentFiles = [ ];
          environment.PENPOT_MCP_REMOTE_MODE = "true";
        };

        penpot-frontend = mkContainer {
          image = "docker.io/penpotapp/frontend:${penpotVersion}";
          dependsOn = [
            "penpot-backend"
            "penpot-exporter"
            "penpot-mcp"
          ];
          ports = [ "127.0.0.1:${toString penpotPort}:8080" ];
          volumes = [ "${assetsRoot}:/opt/data/assets" ];
          environment =
            commonEnvironment
            // bodySizeEnvironment
            // {
              PENPOT_MCP_URI = "http://penpot-mcp:4401";
              PENPOT_MCP_URI_WS = "http://penpot-mcp:4402";
            };
        };
      };
    };
  };

  systemd = {
    tmpfiles.rules = [
      "d ${stateRoot} 0700 root root -"
      "d ${postgresRoot} 0700 root root -"
      "d ${assetsRoot} 0750 1001 1001 -"
    ];

    services = {
      penpot-secrets = {
        description = "Generate Penpot secrets once";
        after = [ "systemd-tmpfiles-setup.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = lib.getExe generateSecrets;
        };
      };

      penpot-network = {
        description = "Create the Penpot Podman network";
        after = [ "podman.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${lib.getExe pkgs.podman} network create --ignore ${networkName}";
        };
      };
    }
    //
      lib.genAttrs
        (map (name: "podman-${name}") [
          "penpot-postgres"
          "penpot-valkey"
          "penpot-backend"
          "penpot-exporter"
          "penpot-mcp"
          "penpot-frontend"
        ])
        (_: {
          requires = podmanDependencies;
          after = podmanDependencies;
        });
  };
}
