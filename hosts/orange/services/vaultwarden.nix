{
  config,
  lib,
  orangeSettings,
  pkgs,
  ...
}:

let
  inherit (config.services.tailnetWeb) tailnetHostname;
  inherit (orangeSettings)
    storageMountUnit
    storageRoot
    vaultwardenBackupRoot
    vaultwardenPort
    ;
  legacyVaultwardenRoot = "${storageRoot}/server/vaultwarden";

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
  services.vaultwarden = {
    enable = true;
    dbBackend = "sqlite";
    backupDir = vaultwardenBackupRoot;
    config = {
      DOMAIN = "https://${tailnetHostname}/vault";
      EXPERIMENTAL_CLIENT_FEATURE_FLAGS = "cxp-import-mobile";
      ROCKET_ADDRESS = "127.0.0.1";
      ROCKET_PORT = vaultwardenPort;
      SIGNUPS_ALLOWED = false;
    };
  };

  systemd = {
    services = {
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
        # Run only from the 06:05 timer, not whenever multi-user.target starts.
        wantedBy = lib.mkForce [ ];
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
    };

    timers.backup-vaultwarden.timerConfig.OnCalendar = "*-*-* 06:05:00";
  };
}
