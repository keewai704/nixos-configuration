{
  lib,
  pkgs,
  ...
}:

let
  inherit (import ../settings.nix)
    storageMountUnit
    storageRoot
    tailnetOrigin
    vaultwardenBackupRoot
    vaultwardenPort
    ;
  legacyVaultwardenRoot = "${storageRoot}/server/vaultwarden";
  storagePreparationDependencies = [
    "media-storage-prepare.service"
    storageMountUnit
  ];
  vaultwardenDependencies = [
    storageMountUnit
    "vaultwarden-import-existing.service"
  ];
  backupDependencies = storagePreparationDependencies ++ [ "vaultwarden-import-existing.service" ];

  importVaultwardenData = pkgs.writeShellApplication {
    name = "import-existing-vaultwarden-data";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.findutils
      pkgs.rsync
      pkgs.sqlite
    ];
    text = ''
      vaultwarden_target="/var/lib/vaultwarden"
      target_database="$vaultwarden_target/db.sqlite3"
      importing_database="$target_database.importing"
      completion_marker="$vaultwarden_target/.legacy-import-complete"
      legacy_root=${lib.escapeShellArg legacyVaultwardenRoot}
      legacy_database=${lib.escapeShellArg "${legacyVaultwardenRoot}/db.sqlite3"}

      validate_database() {
        local database="$1" integrity_result
        integrity_result="$(sqlite3 "$database" 'PRAGMA integrity_check;')"
        if [ "$integrity_result" != "ok" ]; then
          echo "Vaultwarden database failed its integrity check: $database: $integrity_result" >&2
          return 1
        fi
      }

      copy_legacy_items() {
        local item_name source_path target_path importing_path unexpected_path remaining_changes
        for item_name in rsa_key.pem rsa_key.der rsa_key.pub.der attachments sends; do
          source_path="$legacy_root/$item_name"
          target_path="$vaultwarden_target/$item_name"
          [ -e "$source_path" ] || continue
          if [ -L "$source_path" ] || [ -L "$target_path" ]; then
            echo "Refusing a symlink in the Vaultwarden import: $item_name" >&2
            return 1
          fi
          if [ -d "$source_path" ]; then
            install --directory --mode 0700 "$target_path"
            unexpected_path=$(find "$source_path" "$target_path" \
              \( -type l -o \( ! -type d ! -type f \) \) -print -quit)
            if [ -n "$unexpected_path" ]; then
              echo "Refusing an unexpected Vaultwarden import path: $unexpected_path" >&2
              return 1
            fi
            rsync --archive --ignore-existing --delay-updates \
              "$source_path/" "$target_path/"
            remaining_changes=$(rsync --recursive --checksum --dry-run --itemize-changes \
              "$source_path/" "$target_path/")
            if [ -n "$remaining_changes" ]; then
              echo "Vaultwarden import target differs from the legacy source: $item_name" >&2
              printf '%s\n' "$remaining_changes" >&2
              return 1
            fi
          elif [ -f "$source_path" ]; then
            if [ -e "$target_path" ]; then
              [ -f "$target_path" ] || {
                echo "Vaultwarden import target has the wrong type: $target_path" >&2
                return 1
              }
              if ! cmp --silent "$source_path" "$target_path"; then
                echo "Vaultwarden import target differs from the legacy source: $item_name" >&2
                return 1
              fi
              continue
            fi
            importing_path="$target_path.importing"
            if [ -L "$importing_path" ]; then
              echo "Refusing a symlink in the Vaultwarden import state: $importing_path" >&2
              return 1
            fi
            rm --force "$importing_path"
            cp --archive "$source_path" "$importing_path"
            mv "$importing_path" "$target_path"
          else
            echo "Vaultwarden import source has the wrong type: $source_path" >&2
            return 1
          fi
        done
      }

      install --directory --mode 0700 --owner vaultwarden --group vaultwarden "$vaultwarden_target"
      if [ -L "$target_database" ] || [ -L "$completion_marker" ]; then
        echo "Refusing a symlink in the Vaultwarden import state." >&2
        exit 1
      fi

      if [ -e "$completion_marker" ]; then
        if [ ! -s "$target_database" ]; then
          echo "Vaultwarden import is marked complete but its database is missing." >&2
          exit 1
        fi
        validate_database "$target_database"
        echo "Vaultwarden legacy import is already complete."
        exit 0
      fi

      if [ -s "$target_database" ]; then
        validate_database "$target_database"
        copy_legacy_items
        chown --recursive vaultwarden:vaultwarden "$vaultwarden_target"
        chmod 0600 "$target_database"
        install --mode 0600 --owner vaultwarden --group vaultwarden /dev/null "$completion_marker"
        echo "Completed a previously interrupted Vaultwarden legacy import."
        exit 0
      fi

      if [ ! -s "$legacy_database" ]; then
        echo "No existing Vaultwarden database was found at $legacy_database." >&2
        exit 1
      fi

      rm --force "$importing_database"
      sqlite3 -readonly "$legacy_database" \
        ".backup '$importing_database'"

      validate_database "$importing_database"
      copy_legacy_items
      chown --recursive vaultwarden:vaultwarden "$vaultwarden_target"
      mv "$importing_database" "$target_database"
      chmod 0600 "$target_database"
      install --mode 0600 --owner vaultwarden --group vaultwarden /dev/null "$completion_marker"
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
      DOMAIN = "${tailnetOrigin}/vault";
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
        requires = storagePreparationDependencies;
        after = storagePreparationDependencies;
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
        requires = vaultwardenDependencies;
        after = vaultwardenDependencies;
      };

      backup-vaultwarden = {
        # Run only from the 06:05 timer, not whenever multi-user.target starts.
        wantedBy = lib.mkForce [ ];
        requires = backupDependencies;
        after = backupDependencies;
      };
    };

    timers.backup-vaultwarden.timerConfig.OnCalendar = "*-*-* 06:05:00";
  };
}
