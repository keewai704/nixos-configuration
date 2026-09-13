backup_root=@localBackupRoot@
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
  --file "$minecraft_tmp" --directory / @minecraftArchivePath@
mv "$minecraft_tmp" "$minecraft_dir/minecraft-$stamp.tar.zst"

restart_minecraft
trap - EXIT

if [[ ! -s @vaultwardenDatabase@ ]]; then
  echo 'The current Vaultwarden backup is missing' >&2
  exit 1
fi
vaultwarden_backup_age=$(( $(date +%s) - $(stat --format %Y @vaultwardenDatabase@) ))
if (( vaultwarden_backup_age > 3600 )); then
  echo 'The current Vaultwarden backup is more than one hour old' >&2
  exit 1
fi
vaultwarden_tmp="$vaultwarden_dir/.vaultwarden-$stamp.tar.zst.tmp"
tar --create --zstd --acls --xattrs --numeric-owner \
  --file "$vaultwarden_tmp" \
  --directory @vaultwardenBackupRoot@ .
mv "$vaultwarden_tmp" "$vaultwarden_dir/vaultwarden-$stamp.tar.zst"

find "$minecraft_dir" -mindepth 1 -maxdepth 1 -type f \
  -name 'minecraft-*.tar.zst' -mtime +13 -delete
find "$vaultwarden_dir" -mindepth 1 -maxdepth 1 -type f \
  -name 'vaultwarden-*.tar.zst' -mtime +13 -delete
