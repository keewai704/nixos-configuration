{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (import ./settings.nix)
    localBackupRoot
    minecraftDataDir
    smartDevices
    storageMountUnit
    storageRoot
    vaultwardenBackupRoot
    ;

  localBackup = pkgs.writeShellApplication {
    name = "orange-local-backup";
    runtimeInputs = with pkgs; [
      coreutils
      findutils
      gnutar
      systemd
      zstd
    ];
    text = ''
      set -euo pipefail

      backup_root=${lib.escapeShellArg localBackupRoot}
      minecraft_dir="$backup_root/minecraft"
      vaultwarden_dir="$backup_root/vaultwarden"
      stamp=$(date +%Y%m%dT%H%M%S)
      minecraft_was_active=false

      install -d -m 0700 "$backup_root" "$minecraft_dir" "$vaultwarden_dir"

      if systemctl is-active --quiet minecraft.service; then
        minecraft_was_active=true
        systemctl stop minecraft.service
      fi

      restart_minecraft() {
        if [[ "$minecraft_was_active" == true ]]; then
          systemctl start minecraft.service
        fi
      }
      trap restart_minecraft EXIT

      minecraft_tmp="$minecraft_dir/.minecraft-$stamp.tar.zst.tmp"
      tar --create --zstd --acls --xattrs --numeric-owner \
        --file "$minecraft_tmp" --directory / ${lib.escapeShellArg (lib.removePrefix "/" minecraftDataDir)}
      mv "$minecraft_tmp" "$minecraft_dir/minecraft-$stamp.tar.zst"

      restart_minecraft
      trap - EXIT

      if [[ ! -s ${lib.escapeShellArg "${vaultwardenBackupRoot}/db.sqlite3"} ]]; then
        echo 'The current Vaultwarden backup is missing' >&2
        exit 1
      fi
      vaultwarden_backup_age=$(( $(date +%s) - $(stat --format %Y ${lib.escapeShellArg "${vaultwardenBackupRoot}/db.sqlite3"}) ))
      if (( vaultwarden_backup_age > 3600 )); then
        echo 'The current Vaultwarden backup is more than one hour old' >&2
        exit 1
      fi
      vaultwarden_tmp="$vaultwarden_dir/.vaultwarden-$stamp.tar.zst.tmp"
      tar --create --zstd --acls --xattrs --numeric-owner \
        --file "$vaultwarden_tmp" \
        --directory ${lib.escapeShellArg vaultwardenBackupRoot} .
      mv "$vaultwarden_tmp" "$vaultwarden_dir/vaultwarden-$stamp.tar.zst"

      find "$minecraft_dir" -mindepth 1 -maxdepth 1 -type f \
        -name 'minecraft-*.tar.zst' -mtime +13 -delete
      find "$vaultwarden_dir" -mindepth 1 -maxdepth 1 -type f \
        -name 'vaultwarden-*.tar.zst' -mtime +13 -delete
    '';
  };

  smartSelfTest =
    testType:
    pkgs.writeShellApplication {
      name = "orange-smart-${testType}";
      runtimeInputs = with pkgs; [ smartmontools ];
      text = ''
        set -euo pipefail
        for device in ${lib.escapeShellArgs smartDevices}; do
          [[ -b "$device" ]] || {
            echo "Missing block device: $device" >&2
            exit 1
          }
          smartctl --test=${testType} "$device"
        done
      '';
    };

  nixStoreVerify = pkgs.writeShellApplication {
    name = "orange-nix-store-verify";
    runtimeInputs = [ config.nix.package ];
    text = ''
      set -euo pipefail
      nix-store --verify --check-contents
    '';
  };
in
{
  services.fstrim.interval = "Mon *-*-* 06:50:00";

  nix = {
    gc.dates = lib.mkForce "Mon *-*-* 07:00:00";
    optimise.dates = lib.mkForce [ "*-*-* 06:40:00" ];
  };

  systemd = {
    suppressedSystemUnits = [ "systemd-tmpfiles-clean.timer" ];

    services = {
      orange-local-backup = {
        description = "Create versioned local backups of orange service state";
        requires = [ storageMountUnit ];
        after = [
          "backup-vaultwarden.service"
          storageMountUnit
        ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = lib.getExe localBackup;
          UMask = "0077";
          Nice = 10;
          IOSchedulingClass = "idle";
          ReadWritePaths = [ "${storageRoot}/server/backups" ];
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
        };
      };

      orange-smart-short = {
        description = "Start weekly SMART short self-tests";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = lib.getExe (smartSelfTest "short");
        };
      };

      orange-smart-long = {
        description = "Start monthly SMART long self-tests";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = lib.getExe (smartSelfTest "long");
        };
      };

      orange-nix-store-verify = {
        description = "Verify Nix Store contents monthly";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = lib.getExe nixStoreVerify;
          Nice = 10;
          IOSchedulingClass = "idle";
        };
      };
    };

    timers = {
      orange-local-backup = {
        description = "Run local service backups after 06:00";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "*-*-* 06:15:00";
          Persistent = false;
        };
      };

      orange-smart-short = {
        description = "Run SMART short self-tests after 06:00 each week";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "Sun *-*-* 06:50:00";
          Persistent = false;
        };
      };

      orange-smart-long = {
        description = "Run SMART long self-tests after 06:00 each month";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "*-*-01 07:30:00";
          Persistent = false;
        };
      };

      orange-nix-store-verify = {
        description = "Verify Nix Store after 06:00 each month";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "*-*-01 08:00:00";
          Persistent = false;
        };
      };

      logrotate = {
        timerConfig = {
          OnCalendar = lib.mkForce "*-*-* 06:20:00";
          Persistent = false;
        };
      };

      orange-tmpfiles-clean = {
        description = "Clean temporary directories after 06:00";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "*-*-* 06:30:00";
          Persistent = false;
          Unit = "systemd-tmpfiles-clean.service";
        };
      };

      backup-vaultwarden.timerConfig.Persistent = lib.mkForce false;
      nix-gc.timerConfig.Persistent = lib.mkForce false;
      nix-optimise.timerConfig = {
        Persistent = lib.mkForce false;
        RandomizedDelaySec = lib.mkForce 0;
      };
      fstrim.timerConfig = {
        Persistent = lib.mkForce false;
        RandomizedDelaySec = lib.mkForce 0;
      };
    };
  };
}
