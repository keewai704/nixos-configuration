backup_root=@localBackupRoot@
minecraft_dir="$backup_root/minecraft"
vaultwarden_dir="$backup_root/vaultwarden"
stamp=$(date +%Y%m%dT%H%M%S)
minecraft_archive_path=@minecraftArchivePath@
minecraft_live_root=@minecraftLiveBackupRoot@
minecraft_staging=
minecraft_tmp="$minecraft_dir/.minecraft-$stamp.tar.zst.tmp"

install -d -m 0700 "$backup_root" "$minecraft_dir" "$vaultwarden_dir"

if [[ ! -s @vaultwardenDatabase@ ]]; then
  echo 'The current Vaultwarden backup is missing' >&2
  exit 1
fi
vaultwarden_backup_age=$(($(date +%s) - $(stat --format %Y @vaultwardenDatabase@)))
if ((vaultwarden_backup_age > 3600)); then
  echo 'The current Vaultwarden backup is more than one hour old' >&2
  exit 1
fi
vaultwarden_tmp="$vaultwarden_dir/.vaultwarden-$stamp.tar.zst.tmp"
tar --create --zstd --acls --xattrs --numeric-owner \
  --file "$vaultwarden_tmp" \
  --directory @vaultwardenBackupRoot@ .
mv "$vaultwarden_tmp" "$vaultwarden_dir/vaultwarden-$stamp.tar.zst"

cleanup_minecraft() {
  rm -f -- "$minecraft_tmp"
  if [[ -n "$minecraft_staging" ]]; then
    rm -rf -- "$minecraft_staging"
  fi
}
trap cleanup_minecraft EXIT

if systemctl is-active --quiet minecraft.service; then
  minecraft_invocation=$(systemctl show minecraft.service --property InvocationID --value)
  minecraft_name="minecraft-$stamp"
  printf 'jeb create full %s\n' "$minecraft_name" | timeout 10 tee /run/minecraft.stdin >/dev/null
  minecraft_deadline=$(($(date +%s) + 900))
  while :; do
    minecraft_zip=$(find "$minecraft_live_root" -mindepth 2 -maxdepth 2 \
      -type f -name "$minecraft_name.zip" -print -quit)
    if [[ -n "$minecraft_zip" ]]; then
      break
    fi
    if ! systemctl is-active --quiet minecraft.service ||
      [[ $(systemctl show minecraft.service --property InvocationID --value) != "$minecraft_invocation" ]]; then
      echo 'Minecraft stopped or restarted during its live backup' >&2
      exit 1
    fi
    if (($(date +%s) >= minecraft_deadline)); then
      echo 'Timed out waiting for the Minecraft backup MOD' >&2
      exit 1
    fi
    sleep 2
  done

  unzip -tqq "$minecraft_zip"
  unzip -p "$minecraft_zip" justenoughbackups.data |
    jq --exit-status '.manifest.type == "FULL" and .status.completed == true and (.status.brokenFiles | length == 0)' >/dev/null
  minecraft_world=$(basename "$(dirname "$minecraft_zip")")
  minecraft_staging=$(mktemp -d "$minecraft_dir/.minecraft-$stamp.XXXXXX")
  tar --create --acls --xattrs --numeric-owner --file - --directory / \
    --exclude "$minecraft_archive_path/$minecraft_world" \
    --exclude "$minecraft_archive_path/logs" "$minecraft_archive_path" |
    tar --extract --acls --xattrs --numeric-owner --file - --directory "$minecraft_staging"
  minecraft_world_snapshot="$minecraft_staging/$minecraft_archive_path/$minecraft_world"
  install -d "$minecraft_world_snapshot"
  unzip -q "$minecraft_zip" -d "$minecraft_world_snapshot" \
    -x justenoughbackups.data
  chown --recursive --reference="/$minecraft_archive_path/$minecraft_world" "$minecraft_world_snapshot"
  chmod --reference="/$minecraft_archive_path/$minecraft_world" "$minecraft_world_snapshot"
  tar --create --zstd --acls --xattrs --numeric-owner \
    --file "$minecraft_tmp" --directory "$minecraft_staging" "$minecraft_archive_path"
else
  tar --create --zstd --acls --xattrs --numeric-owner \
    --file "$minecraft_tmp" --directory / "$minecraft_archive_path"
fi
mv "$minecraft_tmp" "$minecraft_dir/minecraft-$stamp.tar.zst"
cleanup_minecraft
trap - EXIT

find "$minecraft_dir" -mindepth 1 -maxdepth 1 -type f \
  -name 'minecraft-*.tar.zst' -mtime +13 -delete
find "$vaultwarden_dir" -mindepth 1 -maxdepth 1 -type f \
  -name 'vaultwarden-*.tar.zst' -mtime +13 -delete
