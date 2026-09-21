state_dir=${STATE_DIRECTORY:?STATE_DIRECTORY is not set}
runtime_dir=${RUNTIME_DIRECTORY:?RUNTIME_DIRECTORY is not set}
webhook_file=${CREDENTIALS_DIRECTORY:?CREDENTIALS_DIRECTORY is not set}/discord-webhook
new_keys="$runtime_dir/new-keys"
new_messages="$runtime_dir/new-messages"
: >"$new_keys"
: >"$new_messages"

incident_hash() {
  printf '%s' "$1" | sha256sum | cut -d' ' -f1
}

queue_alert() {
  local key="$1" message="$2" hash current_size message_size
  hash=$(incident_hash "$key")
  if [[ ! -e "$state_dir/$hash" ]] && ! grep --fixed-strings --line-regexp --quiet "$hash" "$new_keys"; then
    current_size=$(wc -c <"$new_messages")
    message_size=$(printf -- '- %s\n' "$message" | wc -c)
    if ((current_size > 0 && current_size + message_size > 1700)); then
      return
    fi
    printf -- '- %s\n' "$message" >>"$new_messages"
    printf '%s\n' "$hash" >>"$new_keys"
  fi
}

clear_alert() {
  local hash
  hash=$(incident_hash "$1")
  rm -f "$state_dir/$hash"
}

finish_and_notify() {
  local status=$? payload
  trap - EXIT
  set +o errexit

  if ((status == 0)); then
    clear_alert "monitor-execution"
  else
    queue_alert "monitor-execution" "health monitor exited before completing its checks (status $status)"
  fi

  if [[ -s "$new_messages" ]]; then
    if payload=$(jq --null-input --rawfile details "$new_messages" \
      '{username: "orange health monitor", content: ("🔴 **orangeで異常を検出しました**\n" + ($details[0:1700]))}') &&
      curl --fail --silent --show-error --max-time 20 \
        --retry 2 --retry-all-errors \
        --header 'Content-Type: application/json' \
        --data "$payload" \
        "$(<"$webhook_file")" >/dev/null; then
      while IFS= read -r hash; do
        touch "$state_dir/$hash" || status=1
      done <"$new_keys"
    else
      echo 'Failed to deliver Discord health alert' >&2
      status=1
    fi
  fi

  exit "$status"
}

check_service() {
  local service="$1"
  if systemctl is-active --quiet "$service.service"; then
    clear_alert "service-$service"
  else
    queue_alert "service-$service" "systemd service is not active: $service.service"
  fi
}

check_http() {
  local key="$1" url="$2"
  shift 2
  if curl --fail --silent --show-error --location --max-time 20 "$@" "$url" >/dev/null; then
    clear_alert "http-$key"
  else
    queue_alert "http-$key" "HTTP health check failed: $url"
  fi
}

check_fresh_file() {
  local key="$1" label="$2" path="$3" pattern="$4" max_age_minutes="$5"
  local newest modified now age_minutes

  if [[ ! -d "$path" ]]; then
    queue_alert "backup-$key" "$label directory is missing"
    return
  fi
  if ! newest=$(find "$path" -maxdepth 1 -type f -name "$pattern" -printf '%T@ %p\n' 2>/dev/null |
    sort --numeric-sort | tail -n 1 | cut -d' ' -f2-); then
    queue_alert "backup-$key" "$label backup directory could not be read"
    return
  fi
  if [[ -z "$newest" ]]; then
    queue_alert "backup-$key" "$label backup is missing"
    return
  fi
  if ! modified=$(stat --format %Y "$newest"); then
    queue_alert "backup-$key" "$label backup timestamp could not be read"
    return
  fi

  now=$(date +%s)
  age_minutes=$(((now - modified) / 60))
  if ((age_minutes > max_age_minutes)); then
    queue_alert "backup-$key" "$label backup is stale ($age_minutes minutes old)"
  else
    clear_alert "backup-$key"
  fi
}

check_services() {
  local service failed_units
  for service in @monitoredServices@; do
    check_service "$service"
  done

  failed_units=$(systemctl --failed --no-legend --plain 2>/dev/null |
    awk '$1 != "orange-health-monitor.service" { print $1 }' |
    paste -sd ',' -)
  if [[ -n "$failed_units" ]]; then
    queue_alert "failed-units" "failed systemd units: $failed_units"
  else
    clear_alert "failed-units"
  fi
}

check_storage_mount() {
  local mount_options
  if mountpoint --quiet @storageRootArg@; then
    mount_options=$(findmnt --noheadings --output OPTIONS @storageRootArg@ 2>/dev/null || true)
    if [[ ",$mount_options," == *,rw,* ]]; then
      clear_alert "storage-mount"
    else
      queue_alert "storage-mount" "@storageRoot@ is not mounted read-write"
    fi
  else
    queue_alert "storage-mount" "@storageRoot@ is not mounted"
  fi
}

check_filesystem_space() {
  local disk_usage_read_failed filesystem usage inode_usage key
  disk_usage_read_failed=false
  for filesystem in / /boot @storageRootArg@; do
    if usage=$(df --portability "$filesystem" 2>/dev/null | awk 'NR == 2 { gsub(/%/, "", $5); print $5 }') &&
      [[ "$usage" =~ ^[0-9]+$ ]]; then
      key=$(printf '%s' "$filesystem" | tr '/' '_')
      if ((usage >= 85)); then
        queue_alert "disk-space-$key" "filesystem $filesystem is $usage% full"
      else
        clear_alert "disk-space-$key"
      fi
    else
      disk_usage_read_failed=true
      queue_alert "disk-space-command" "could not read filesystem usage for $filesystem"
    fi

    if inode_usage=$(df --inodes --portability "$filesystem" 2>/dev/null | awk 'NR == 2 { gsub(/%/, "", $5); print $5 }') &&
      [[ "$inode_usage" =~ ^[0-9]+$ ]]; then
      key=$(printf '%s' "$filesystem" | tr '/' '_')
      if ((inode_usage >= 85)); then
        queue_alert "inode-space-$key" "filesystem $filesystem inode usage is $inode_usage%"
      else
        clear_alert "inode-space-$key"
      fi
    fi
  done
  if [[ "$disk_usage_read_failed" == false ]]; then
    clear_alert "disk-space-command"
  fi
}

check_drives() {
  local device key smart_health summary bad_attributes selftest_errors
  for device in @smartDevices@; do
    key=${device##*/}
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

    bad_attributes=$(smartctl --attributes "$device" 2>/dev/null |
      awk '$2 ~ /^(Reallocated_Sector_Ct|Current_Pending_Sector|Offline_Uncorrectable)$/ && $10 ~ /^[0-9]+$/ && $10 != 0 { print $2 "=" $10 }' |
      paste -sd ', ' - || true)
    if [[ -n "$bad_attributes" ]]; then
      queue_alert "smart-attributes-$key" "SMART media errors on $device: $bad_attributes"
    else
      clear_alert "smart-attributes-$key"
    fi

    selftest_errors=$(smartctl --log=selftest "$device" 2>/dev/null |
      grep --extended-regexp '# [0-9]+.*(Completed:|failed|Failure)' |
      grep --invert-match --extended-regexp 'Completed without error|No self-tests have been logged' |
      head -n 3 |
      tr '\n' '; ' || true)
    if [[ -n "$selftest_errors" ]]; then
      queue_alert "smart-selftest-$key" "SMART self-test failure on $device: $selftest_errors"
    else
      clear_alert "smart-selftest-$key"
    fi
  done
}

check_memory() {
  local memory_available swap_usage
  memory_available=$(awk '/MemAvailable:/ { available=$2 } /MemTotal:/ { total=$2 } END { if (total > 0) print int(available * 100 / total) }' /proc/meminfo)
  if [[ "$memory_available" =~ ^[0-9]+$ ]] && ((memory_available < 10)); then
    queue_alert "memory-pressure" "available memory is only $memory_available%"
  else
    clear_alert "memory-pressure"
  fi

  swap_usage=$(awk '/SwapTotal:/ { total=$2 } /SwapFree:/ { free=$2 } END { if (total > 0) print int((total - free) * 100 / total); else print 0 }' /proc/meminfo)
  if [[ "$swap_usage" =~ ^[0-9]+$ ]] && ((swap_usage >= 75)); then
    queue_alert "swap-pressure" "swap usage is $swap_usage%"
  else
    clear_alert "swap-pressure"
  fi
}

check_temperature() {
  local highest_temperature temperature_file temperature
  highest_temperature=0
  for temperature_file in /sys/class/thermal/thermal_zone*/temp /sys/class/hwmon/hwmon*/temp*_input; do
    [[ -r "$temperature_file" ]] || continue
    temperature=$(<"$temperature_file")
    [[ "$temperature" =~ ^[0-9]+$ ]] || continue
    ((temperature > highest_temperature)) && highest_temperature=$temperature
  done
  if ((highest_temperature >= 90000)); then
    queue_alert "temperature" "hardware temperature reached $((highest_temperature / 1000)) C"
  else
    clear_alert "temperature"
  fi
}

check_recent_errors() {
  local recent_kernel_errors recent_oom recent_coredumps
  recent_kernel_errors=$(journalctl --dmesg --since '-16 minutes' --priority err..alert --no-pager --output cat 2>/dev/null |
    sed '/^$/d' | tail -n 8 | tr '\n' '; ' || true)
  if [[ -n "$recent_kernel_errors" ]]; then
    queue_alert "kernel-errors" "recent kernel errors: $recent_kernel_errors"
  else
    clear_alert "kernel-errors"
  fi

  recent_oom=$(journalctl --dmesg --since '-16 minutes' --no-pager --output cat 2>/dev/null |
    grep --ignore-case --extended-regexp 'out of memory|oom-kill|killed process' |
    tail -n 5 | tr '\n' '; ' || true)
  if [[ -n "$recent_oom" ]]; then
    queue_alert "oom" "recent OOM event: $recent_oom"
  else
    clear_alert "oom"
  fi

  recent_coredumps=$(journalctl --since '-16 minutes' --identifier systemd-coredump --no-pager --output cat 2>/dev/null |
    grep --extended-regexp 'dumped core|Process .* of user' |
    tail -n 5 | tr '\n' '; ' || true)
  if [[ -n "$recent_coredumps" ]]; then
    queue_alert "coredumps" "recent process coredump: $recent_coredumps"
  else
    clear_alert "coredumps"
  fi
}

check_clock() {
  if [[ $(timedatectl show --property NTPSynchronized --value 2>/dev/null) == yes ]]; then
    clear_alert "time-sync"
  else
    queue_alert "time-sync" "system clock is not synchronized"
  fi
}

check_tailnet() {
  local tailscale_json serve_status serve_count summary
  tailscale_json=$(tailscale status --json 2>/dev/null || true)
  if jq --exit-status '.BackendState == "Running" and .Self.Online == true' >/dev/null 2>&1 <<<"$tailscale_json"; then
    clear_alert "tailscale-status"
  else
    queue_alert "tailscale-status" "Tailscale is not online"
  fi

  serve_status=$(tailscale serve status 2>&1 || true)
  serve_count=$(grep --count '^https://' <<<"$serve_status" || true)
  if ((serve_count == 1)) &&
    grep --fixed-strings --quiet '@tailnetOrigin@ (tailnet only)' <<<"$serve_status" &&
    grep --fixed-strings --quiet 'proxy http://127.0.0.1:@nginxPort@' <<<"$serve_status"; then
    clear_alert "tailscale-serve"
  else
    summary=$(tr '\n' ' ' <<<"$serve_status" | cut -c1-300)
    queue_alert "tailscale-serve" "unexpected Tailscale Serve configuration: $summary"
  fi
}

check_web_services() {
  local icloud_status
  check_http "nginx" "http://127.0.0.1:@nginxPort@/" --header 'Host: @tailnetHostname@'
  check_http "immich" "@tailnetOrigin@/"
  check_http "vaultwarden" "@tailnetOrigin@/vault/"
  if icloud_status=$(curl --silent --show-error --max-time 10 --output /dev/null --write-out '%{http_code}' \
    --header 'Host: @tailnetHostname@' 'http://127.0.0.1:@icloudKeychainPort@/icloud-keychain/') &&
    [[ "$icloud_status" == 401 ]]; then
    clear_alert "http-icloud-keychain"
  else
    queue_alert "http-icloud-keychain" "iCloud Keychain backend did not return the expected unauthenticated HTTP 401"
  fi
}

check_tcp_services() {
  local port_and_name port name
  for port_and_name in '@minecraftPort@ minecraft' '445 samba'; do
    read -r port name <<<"$port_and_name"
    if nc -z -w 3 127.0.0.1 "$port" >/dev/null 2>&1; then
      clear_alert "tcp-$name"
    else
      queue_alert "tcp-$name" "TCP health check failed for $name on port $port"
    fi
  done
}

check_backend_listeners() {
  local exposed_backends
  if exposed_backends=$(ss --listening --tcp --numeric --no-header 2>/dev/null |
    awk '$4 ~ /:(@loopbackBackendPortPattern@)$/ && $4 !~ /^127\.0\.0\.1:/ && $4 !~ /^\[::1\]:/ { print $4 }' |
    paste -sd ', ' -); then
    clear_alert "backend-listeners-check"
    if [[ -n "$exposed_backends" ]]; then
      queue_alert "backend-listeners" "application backend is not loopback-only: $exposed_backends"
    else
      clear_alert "backend-listeners"
    fi
  else
    queue_alert "backend-listeners-check" "could not inspect application backend listeners"
  fi
}

check_backups() {
  local local_backup_trigger
  check_fresh_file "immich" "Immich database" @immichBackupRoot@ 'immich-db-backup-*.sql.gz' 1800
  check_fresh_file "vaultwarden" "Vaultwarden" @vaultwardenBackupRoot@ 'db.sqlite3' 1800

  local_backup_trigger=$(systemctl show orange-local-backup.timer --property LastTriggerUSec --value 2>/dev/null || true)
  if [[ -n "$local_backup_trigger" && "$local_backup_trigger" != n/a ]]; then
    check_fresh_file "minecraft" "Minecraft" @minecraftBackupRoot@ 'minecraft-*.tar.zst' 1800
    check_fresh_file "vaultwarden-versioned" "versioned Vaultwarden" @versionedVaultwardenBackupRoot@ 'vaultwarden-*.tar.zst' 1800
  fi
}

check_kernel() {
  local booted_kernel current_kernel
  clear_alert "system-generation"

  booted_kernel=$(readlink --canonicalize /run/booted-system/kernel 2>/dev/null || true)
  current_kernel=$(readlink --canonicalize /run/current-system/kernel 2>/dev/null || true)
  if [[ -n "$booted_kernel" && "$booted_kernel" == "$current_kernel" ]]; then
    clear_alert "kernel-reboot"
  else
    queue_alert "kernel-reboot" "a reboot is required to run the configured kernel"
  fi
}

main() {
  check_services
  check_storage_mount
  check_filesystem_space
  check_drives
  check_memory
  check_temperature
  check_recent_errors
  check_clock
  check_tailnet
  check_web_services
  check_tcp_services
  check_backend_listeners
  check_backups
  check_kernel
}

trap finish_and_notify EXIT
main
