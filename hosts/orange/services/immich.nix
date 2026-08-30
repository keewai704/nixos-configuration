{
  lib,
  pkgs,
  ...
}:

let
  inherit (import ../settings.nix)
    immichBackupRoot
    immichMediaRoot
    immichPort
    storageMountUnit
    tailnetOrigin
    ;
  postgresqlPackage = pkgs.postgresql_17;
  importDependencies = [
    "media-storage-prepare.service"
    storageMountUnit
    "postgresql-setup.service"
  ];
  serverDependencies = [
    "media-storage-prepare.service"
    storageMountUnit
    "immich-import-existing-database.service"
  ];

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
in
{
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
    immich = {
      enable = true;
      host = "127.0.0.1";
      port = immichPort;
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
          cronExpression = "0 6 * * *";
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
        server.externalDomain = tailnetOrigin;
      };
    };

    # Pin the database major version so an ordinary flake update cannot perform
    # an implicit PostgreSQL major upgrade on the SSD.
    postgresql.package = postgresqlPackage;
  };

  systemd.services = {
    immich-import-existing-database = {
      description = "Import the existing Immich PostgreSQL backup once";
      requires = importDependencies;
      after = importDependencies;
      before = [ "immich-server.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe importImmichDatabase;
      };
    };

    immich-server = {
      requires = serverDependencies;
      after = serverDependencies;
      serviceConfig.ReadWritePaths = [ immichMediaRoot ];
    };
  };
}
