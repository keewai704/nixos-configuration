{
  config,
  lib,
  pkgs,
  ...
}:

let
  storageRoot = "/srv/storage";
  storageMountUnit = "srv-storage.mount";
  backupRoot = "${storageRoot}/server/backups/orange-local";
  vaultwardenBackupRoot = "${storageRoot}/server/backups/vaultwarden-nixos";
  immichBackupRoot = "${storageRoot}/Pictures/backups";
  tailnetHostname = "orange.tail1e65cd.ts.net";

  healthMonitor = pkgs.writeShellApplication {
    name = "orange-health-monitor";
    runtimeInputs = with pkgs; [
      coreutils
      curl
      findutils
      gawk
      gnugrep
      gnused
      iproute2
      jq
      netcat-openbsd
      smartmontools
      systemd
      tailscale
      util-linux
    ];
    text = ''
      set -u -o pipefail

      state_dir=''${STATE_DIRECTORY:?STATE_DIRECTORY is not set}
      runtime_dir=''${RUNTIME_DIRECTORY:?RUNTIME_DIRECTORY is not set}
      webhook_file=''${CREDENTIALS_DIRECTORY:?CREDENTIALS_DIRECTORY is not set}/discord-webhook
      new_keys="$runtime_dir/new-keys"
      new_messages="$runtime_dir/new-messages"
      : >"$new_keys"
      : >"$new_messages"

      incident_hash() {
        printf '%s' "$1" | sha256sum | cut -d' ' -f1
      }

      queue_alert() {
        local key="$1" message="$2" hash
        hash=$(incident_hash "$key")
        if [[ ! -e "$state_dir/$hash" ]] && ! grep --fixed-strings --line-regexp --quiet "$hash" "$new_keys"; then
          printf '%s\n' "$hash" >>"$new_keys"
          printf -- '- %s\n' "$message" >>"$new_messages"
        fi
      }

      clear_alert() {
        local hash
        hash=$(incident_hash "$1")
        rm -f "$state_dir/$hash"
      }

      check_service() {
        local service="$1"
        if systemctl is-active --quiet "$service.service"; then
          clear_alert "service-$service"
        else
          queue_alert "service-$service" "systemd service is not active: $service.service"
        fi
      }

      for service in \
        NetworkManager tailscaled sshd samba-smbd immich-server postgresql \
        redis-immich vaultwarden nginx minecraft camofox yepanywhere \
        tailscale-serve-nginx; do
        check_service "$service"
      done

      failed_units=$(systemctl --failed --no-legend --plain 2>/dev/null | awk '{print $1}' | paste -sd ', ' -)
      if [[ -n "$failed_units" ]]; then
        queue_alert "failed-units" "failed systemd units: $failed_units"
      else
        clear_alert "failed-units"
      fi

      if mountpoint --quiet ${lib.escapeShellArg storageRoot}; then
        mount_options=$(findmnt --noheadings --output OPTIONS ${lib.escapeShellArg storageRoot} 2>/dev/null || true)
        if [[ ",$mount_options," == *,rw,* ]]; then
          clear_alert "storage-mount"
        else
          queue_alert "storage-mount" "${storageRoot} is not mounted read-write"
        fi
      else
        queue_alert "storage-mount" "${storageRoot} is not mounted"
      fi

      disk_usage_read_failed=false
      for filesystem in / /boot ${lib.escapeShellArg storageRoot}; do
        if usage=$(df --portability "$filesystem" 2>/dev/null | awk 'NR == 2 { gsub(/%/, "", $5); print $5 }') \
          && [[ "$usage" =~ ^[0-9]+$ ]]; then
          key=$(printf '%s' "$filesystem" | tr '/' '_')
          if (( usage >= 85 )); then
            queue_alert "disk-space-$key" "filesystem $filesystem is $usage% full"
          else
            clear_alert "disk-space-$key"
          fi
        else
          disk_usage_read_failed=true
          queue_alert "disk-space-command" "could not read filesystem usage for $filesystem"
        fi

        if inode_usage=$(df --inodes --portability "$filesystem" 2>/dev/null | awk 'NR == 2 { gsub(/%/, "", $5); print $5 }') \
          && [[ "$inode_usage" =~ ^[0-9]+$ ]]; then
          key=$(printf '%s' "$filesystem" | tr '/' '_')
          if (( inode_usage >= 85 )); then
            queue_alert "inode-space-$key" "filesystem $filesystem inode usage is $inode_usage%"
          else
            clear_alert "inode-space-$key"
          fi
        fi
      done
      if [[ "$disk_usage_read_failed" == false ]]; then
        clear_alert "disk-space-command"
      fi

      for device in /dev/sda /dev/sdb; do
        key=''${device##*/}
        if [[ ! -b "$device" ]]; then
          queue_alert "smart-$key" "block device is missing: $device"
          continue
        fi

        smart_health=$(smartctl --health "$device" 2>&1 || true)
        if grep --ignore-case --extended-regexp --quiet \
          'overall-health.*PASSED|SMART Health Status: OK' <<<"$smart_health"; then
          clear_alert "smart-$key"
        else
          summary=$(tr '\n' ' ' <<<"$smart_health" | cut -c1-240)
          queue_alert "smart-$key" "SMART health check failed for $device: $summary"
        fi

        bad_attributes=$(smartctl --attributes "$device" 2>/dev/null \
          | awk '$2 ~ /^(Reallocated_Sector_Ct|Current_Pending_Sector|Offline_Uncorrectable)$/ && $10 ~ /^[0-9]+$/ && $10 != 0 { print $2 "=" $10 }' \
          | paste -sd ', ' -)
        if [[ -n "$bad_attributes" ]]; then
          queue_alert "smart-attributes-$key" "SMART media errors on $device: $bad_attributes"
        else
          clear_alert "smart-attributes-$key"
        fi

        selftest_errors=$(smartctl --log=selftest "$device" 2>/dev/null \
          | grep --extended-regexp '# [0-9]+.*(Completed:|failed|Failure)' \
          | grep --invert-match --extended-regexp 'Completed without error|No self-tests have been logged' \
          | head -n 3 \
          | tr '\n' '; ' || true)
        if [[ -n "$selftest_errors" ]]; then
          queue_alert "smart-selftest-$key" "SMART self-test failure on $device: $selftest_errors"
        else
          clear_alert "smart-selftest-$key"
        fi
      done

      memory_available=$(awk '/MemAvailable:/ { available=$2 } /MemTotal:/ { total=$2 } END { if (total > 0) print int(available * 100 / total) }' /proc/meminfo)
      if [[ "$memory_available" =~ ^[0-9]+$ ]] && (( memory_available < 10 )); then
        queue_alert "memory-pressure" "available memory is only $memory_available%"
      else
        clear_alert "memory-pressure"
      fi

      swap_usage=$(awk '/SwapTotal:/ { total=$2 } /SwapFree:/ { free=$2 } END { if (total > 0) print int((total - free) * 100 / total); else print 0 }' /proc/meminfo)
      if [[ "$swap_usage" =~ ^[0-9]+$ ]] && (( swap_usage >= 75 )); then
        queue_alert "swap-pressure" "swap usage is $swap_usage%"
      else
        clear_alert "swap-pressure"
      fi

      highest_temperature=0
      for temperature_file in /sys/class/thermal/thermal_zone*/temp /sys/class/hwmon/hwmon*/temp*_input; do
        [[ -r "$temperature_file" ]] || continue
        temperature=$(<"$temperature_file")
        [[ "$temperature" =~ ^[0-9]+$ ]] || continue
        (( temperature > highest_temperature )) && highest_temperature=$temperature
      done
      if (( highest_temperature >= 90000 )); then
        queue_alert "temperature" "hardware temperature reached $((highest_temperature / 1000)) C"
      else
        clear_alert "temperature"
      fi

      recent_kernel_errors=$(journalctl --kernel --since '-16 minutes' --priority err..alert --no-pager --output cat 2>/dev/null \
        | sed '/^$/d' | tail -n 8 | tr '\n' '; ' || true)
      if [[ -n "$recent_kernel_errors" ]]; then
        queue_alert "kernel-errors" "recent kernel errors: $recent_kernel_errors"
      else
        clear_alert "kernel-errors"
      fi

      recent_oom=$(journalctl --kernel --since '-16 minutes' --no-pager --output cat 2>/dev/null \
        | grep --ignore-case --extended-regexp 'out of memory|oom-kill|killed process' \
        | tail -n 5 | tr '\n' '; ' || true)
      if [[ -n "$recent_oom" ]]; then
        queue_alert "oom" "recent OOM event: $recent_oom"
      else
        clear_alert "oom"
      fi

      recent_coredumps=$(journalctl --since '-16 minutes' --identifier systemd-coredump --no-pager --output cat 2>/dev/null \
        | grep --extended-regexp 'dumped core|Process .* of user' \
        | tail -n 5 | tr '\n' '; ' || true)
      if [[ -n "$recent_coredumps" ]]; then
        queue_alert "coredumps" "recent process coredump: $recent_coredumps"
      else
        clear_alert "coredumps"
      fi

      if [[ $(timedatectl show --property NTPSynchronized --value 2>/dev/null) == yes ]]; then
        clear_alert "time-sync"
      else
        queue_alert "time-sync" "system clock is not synchronized"
      fi

      tailscale_json=$(tailscale status --json 2>/dev/null || true)
      if jq --exit-status '.BackendState == "Running" and .Self.Online == true' >/dev/null 2>&1 <<<"$tailscale_json"; then
        clear_alert "tailscale-status"
      else
        queue_alert "tailscale-status" "Tailscale is not online"
      fi

      serve_status=$(tailscale serve status 2>&1 || true)
      serve_count=$(grep --count '^https://' <<<"$serve_status" || true)
      if (( serve_count == 1 )) \
        && grep --fixed-strings --quiet 'https://${tailnetHostname} (tailnet only)' <<<"$serve_status" \
        && grep --fixed-strings --quiet 'proxy http://127.0.0.1:8000' <<<"$serve_status"; then
        clear_alert "tailscale-serve"
      else
        summary=$(tr '\n' ' ' <<<"$serve_status" | cut -c1-300)
        queue_alert "tailscale-serve" "unexpected Tailscale Serve configuration: $summary"
      fi

      check_http() {
        local key="$1" url="$2"
        shift 2
        if curl --fail --silent --show-error --location --max-time 20 "$@" "$url" >/dev/null; then
          clear_alert "http-$key"
        else
          queue_alert "http-$key" "HTTP health check failed: $url"
        fi
      }

      check_http "camofox" "http://127.0.0.1:9377/health"
      check_http "nginx" "http://127.0.0.1:8000/" --header 'Host: ${tailnetHostname}'
      check_http "immich" "https://${tailnetHostname}/"
      check_http "vaultwarden" "https://${tailnetHostname}/vault/"
      check_http "yep" "https://${tailnetHostname}/yep/"
      check_http "browser" "https://${tailnetHostname}/browser/"

      for port_and_name in '25565 minecraft' '445 samba'; do
        read -r port name <<<"$port_and_name"
        if nc -z -w 3 127.0.0.1 "$port" >/dev/null 2>&1; then
          clear_alert "tcp-$name"
        else
          queue_alert "tcp-$name" "TCP health check failed for $name on port $port"
        fi
      done

      exposed_backends=$(ss --listening --tcp --numeric --no-header 2>/dev/null \
        | awk '$4 ~ /:(2283|8000|3400|8222|9377)$/ && $4 !~ /^127\.0\.0\.1:/ && $4 !~ /^\[::1\]:/ { print $4 }' \
        | paste -sd ', ' -)
      if [[ -n "$exposed_backends" ]]; then
        queue_alert "backend-listeners" "application backend is not loopback-only: $exposed_backends"
      else
        clear_alert "backend-listeners"
      fi

      check_fresh_file() {
        local key="$1" label="$2" path="$3" pattern="$4" max_age_minutes="$5"
        local newest age_minutes now
        newest=$(find "$path" -maxdepth 1 -type f -name "$pattern" -printf '%T@ %p\n' 2>/dev/null \
          | sort --numeric-sort --reverse | head -n 1 | cut -d' ' -f2-)
        if [[ -z "$newest" ]]; then
          queue_alert "backup-$key" "$label backup is missing"
          return
        fi
        now=$(date +%s)
        age_minutes=$(( (now - $(stat --format %Y "$newest")) / 60 ))
        if (( age_minutes > max_age_minutes )); then
          queue_alert "backup-$key" "$label backup is stale ($age_minutes minutes old)"
        else
          clear_alert "backup-$key"
        fi
      }

      check_fresh_file "immich" "Immich database" ${lib.escapeShellArg immichBackupRoot} 'immich-db-backup-*.sql.gz' 1800
      check_fresh_file "vaultwarden" "Vaultwarden" ${lib.escapeShellArg vaultwardenBackupRoot} 'db.sqlite3' 1800

      local_backup_trigger=$(systemctl show orange-local-backup.timer --property LastTriggerUSec --value 2>/dev/null || true)
      if [[ -n "$local_backup_trigger" && "$local_backup_trigger" != n/a ]]; then
        check_fresh_file "minecraft" "Minecraft" ${lib.escapeShellArg "${backupRoot}/minecraft"} 'minecraft-*.tar.zst' 1800
        check_fresh_file "vaultwarden-versioned" "versioned Vaultwarden" ${lib.escapeShellArg "${backupRoot}/vaultwarden"} 'vaultwarden-*.tar.zst' 1800
      fi

      clear_alert "system-generation"

      booted_kernel=$(readlink --canonicalize /run/booted-system/kernel 2>/dev/null || true)
      current_kernel=$(readlink --canonicalize /run/current-system/kernel 2>/dev/null || true)
      if [[ -n "$booted_kernel" && "$booted_kernel" == "$current_kernel" ]]; then
        clear_alert "kernel-reboot"
      else
        queue_alert "kernel-reboot" "a reboot is required to run the configured kernel"
      fi

      if [[ -s "$new_messages" ]]; then
        payload=$(jq --null-input --rawfile details "$new_messages" \
          '{username: "orange health monitor", content: ("🔴 **orangeで異常を検出しました**\n" + ($details[0:1700]))}')
        if curl --fail --silent --show-error --max-time 20 \
          --retry 2 --retry-all-errors \
          --header 'Content-Type: application/json' \
          --data "$payload" \
          "$(<"$webhook_file")" >/dev/null; then
          while IFS= read -r hash; do
            touch "$state_dir/$hash"
          done <"$new_keys"
        else
          echo 'Failed to deliver Discord health alert' >&2
          exit 1
        fi
      fi
    '';
  };

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

      backup_root=${lib.escapeShellArg backupRoot}
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
        --file "$minecraft_tmp" --directory / var/lib/minecraft
      mv "$minecraft_tmp" "$minecraft_dir/minecraft-$stamp.tar.zst"

      restart_minecraft
      minecraft_was_active=false
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
        for device in /dev/sda /dev/sdb; do
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
  age.secrets.discord-webhook = {
    file = ../../secrets/discord-webhook.age;
    mode = "0400";
    owner = "root";
    group = "root";
  };

  services.fstrim.interval = lib.mkForce "Mon *-*-* 06:50:00";

  nix = {
    gc.dates = lib.mkForce "Mon *-*-* 07:00:00";
    optimise.dates = lib.mkForce [ "*-*-* 06:40:00" ];
  };

  systemd = {
    suppressedSystemUnits = [ "systemd-tmpfiles-clean.timer" ];

    services = {
      orange-health-monitor = {
        description = "Monitor orange and notify Discord only on new failures";
        wants = [ "network-online.target" ];
        after = [
          "agenix.service"
          "camofox.service"
          "immich-server.service"
          "minecraft.service"
          "network-online.target"
          "nginx.service"
          "postgresql.service"
          "redis-immich.service"
          "samba-smbd.service"
          "sshd.service"
          "tailscale-serve-nginx.service"
          "tailscaled.service"
          "vaultwarden.service"
          "yepanywhere.service"
        ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = lib.getExe healthMonitor;
          LoadCredential = "discord-webhook:${config.age.secrets.discord-webhook.path}";
          StateDirectory = "orange-health-monitor";
          StateDirectoryMode = "0700";
          RuntimeDirectory = "orange-health-monitor";
          RuntimeDirectoryMode = "0700";
          UMask = "0077";
          NoNewPrivileges = true;
          PrivateTmp = true;
          # "strict" remounts /srv read-only in this service's namespace and
          # would make the host's writable storage mount look unhealthy.
          ProtectSystem = "full";
          ProtectHome = true;
          ProtectClock = true;
          ProtectControlGroups = true;
          ProtectKernelLogs = false;
          ProtectKernelModules = true;
          ProtectKernelTunables = true;
          RestrictAddressFamilies = [
            "AF_UNIX"
            "AF_INET"
            "AF_INET6"
          ];
        };
      };

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
      orange-health-monitor = {
        description = "Check orange health every 15 minutes";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "10min";
          OnUnitActiveSec = "15min";
          AccuracySec = "1min";
        };
      };

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
