backup_root=@localBackupRoot@
vaultwarden_dir="$backup_root/vaultwarden"
stamp=$(date +%Y%m%dT%H%M%S)
vaultwarden_tmp="$vaultwarden_dir/.vaultwarden-$stamp.tar.zst.tmp"

install -d -m 0700 "$backup_root" "$vaultwarden_dir"

trap 'rm -f -- "$vaultwarden_tmp"' EXIT
trap 'exit 143' TERM
trap 'exit 130' INT

find "$vaultwarden_dir" -regextype posix-extended -mindepth 1 -maxdepth 1 -type f \
  -regex '.*/[.]vaultwarden-[0-9]{8}T[0-9]{6}[.]tar[.]zst[.]tmp' -delete

if [[ $(systemctl show backup-vaultwarden.service --property Result --value) != success ]]; then
  echo 'The current Vaultwarden backup failed' >&2
  exit 1
fi
if [[ ! -s @vaultwardenDatabase@ ]]; then
  echo 'The current Vaultwarden backup is missing' >&2
  exit 1
fi
vaultwarden_backup_age=$(($(date +%s) - $(stat --format %Y @vaultwardenDatabase@)))
if ((vaultwarden_backup_age > 3600)); then
  echo 'The current Vaultwarden backup is more than one hour old' >&2
  exit 1
fi
tar --create --zstd --acls --xattrs --numeric-owner \
  --file "$vaultwarden_tmp" \
  --directory @vaultwardenBackupRoot@ .
mv "$vaultwarden_tmp" "$vaultwarden_dir/vaultwarden-$stamp.tar.zst"
find "$vaultwarden_dir" -mindepth 1 -maxdepth 1 -type f \
  -name 'vaultwarden-*.tar.zst' -mtime +13 -delete
