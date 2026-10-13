{
  writeShellApplication,
  nodejs,
  util-linux,
}:
writeShellApplication {
  name = "dsh-storage-migrate";
  runtimeInputs = [ nodejs ];
  runtimeEnv.DSH_MIGRATE_FLOCK = "${util-linux}/bin/flock";
  text = ''
    exec node ${./operations}/migrate-cli.mjs "$@"
  '';
  meta.description = "Offline DSH versioned cache migration with recoverable snapshots";
}
