immich_database="immich"

schema_present="$(@utilLinux@/bin/runuser -u postgres -- \
  @postgresqlPackage@/bin/psql \
    --dbname "$immich_database" \
    --tuples-only \
    --no-align \
    --command "SELECT to_regclass('public.kysely_migrations') IS NOT NULL;")"

if [ "$schema_present" = "t" ]; then
  echo "Immich database already contains a schema; skipping the legacy import."
  exit 0
fi

immich_backup="$(
  find @immichBackupRootArg@ \
    -maxdepth 1 \
    -type f \
    -name 'immich-db-backup-*.sql.gz' \
    -printf '%T@ %p\n' \
    | sort --numeric-sort --reverse \
    | head --lines 1 \
    | cut --delimiter ' ' --fields 2-
)"

if [ -z "$immich_backup" ]; then
  echo "No existing Immich database backup was found in @immichBackupRoot@." >&2
  exit 1
fi

echo "Importing the existing Immich database from $immich_backup"
gzip --test "$immich_backup"
gzip --decompress --stdout "$immich_backup" \
  | @utilLinux@/bin/runuser -u postgres -- \
    @postgresqlPackage@/bin/psql \
      --dbname "$immich_database" \
      --single-transaction \
      --set ON_ERROR_STOP=on

@utilLinux@/bin/runuser -u postgres -- \
  @postgresqlPackage@/bin/psql \
    --dbname "$immich_database" \
    --command "ANALYZE;"
