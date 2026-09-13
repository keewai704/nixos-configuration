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
    text =
      let
        substitutions = {
          "@utilLinux@" = toString pkgs.util-linux;
          "@postgresqlPackage@" = toString postgresqlPackage;
          "@immichBackupRootArg@" = lib.escapeShellArg immichBackupRoot;
          "@immichBackupRoot@" = immichBackupRoot;
        };
      in
      lib.replaceStrings (lib.attrNames substitutions) (lib.attrValues substitutions) (
        builtins.readFile ./import-immich-database.sh
      );
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

      machine-learning.enable = false;
      environment = {
        IMMICH_MACHINE_LEARNING_ENABLED = "false";
        LIBVA_DRIVER_NAME = "iHD";
      };

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

    postgresql.package = postgresqlPackage;
  };

  systemd.tmpfiles.settings.immich.${immichMediaRoot}.e = {
    user = lib.mkForce "keewai";
    group = lib.mkForce "immich-media";
    mode = lib.mkForce "0770";
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
