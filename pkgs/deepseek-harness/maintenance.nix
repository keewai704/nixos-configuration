{
  lib,
  writeShellApplication,
  nodejs,
  util-linux,
  dsh-kernel,
  nodeModules,
}:
writeShellApplication {
  name = "dsh-maintenance";
  runtimeInputs = [ nodejs ];
  runtimeEnv = {
    DSH_RETENTION_FLOCK = "${util-linux}/bin/flock";
    DSH_RETENTION_NODE_MODULES = nodeModules;
    DSH_RETENTION_CATALOG = "${dsh-kernel}/lib/deepseek-harness/node_modules/@deepseek-ai/dsh-session-format-catalog/lib/index.js";
  };
  text = ''
    if [[ ''${1:-} == --help || ''${1:-} == -h ]]; then
      printf '%s\n' \
        'Offline DSH maintenance: stop all packaged DSH processes first.' \
        'Preview only:' \
        '  dsh-maintenance preview --home /absolute/DSH_HOME --id SESSION_ID' \
        '  dsh-maintenance preview --home /absolute/DSH_HOME --older-than 2026-01-01T00:00:00Z' \
        'Apply: repeat selectors and copy asOf, planHash, confirmationToken from the preview:' \
        '  dsh-maintenance apply --home /absolute/DSH_HOME --id SESSION_ID --as-of TIMESTAMP --plan-hash HASH --confirm DELETE:HASH' \
        'Optional: --max 100 --gc-attachments --attachment-grace-days 7' \
        'GC scans supported local references and refuses unknown plugins, backends, formats or dirty SQLite sidecars.' \
        'Workspace-v2 selected session IDs are pruned before deleting logs, with a recoverable journal.' \
        'Recover interrupted workspace metadata: dsh-maintenance recover-workspace --home /absolute/DSH_HOME --confirm RECOVER-WORKSPACE' \
        'No automatic deletion or secure erasure. Exports, external backups, credentials and remote-provider copies remain.' \
        'Log/attachment unlinks cannot be undone; metadata recovery never restores deleted logs.'
      exit 0
    fi
    exec node ${./operations}/maintenance.mjs "$@"
  '';
  meta.description = "Offline confirmed DSH retention with exclusive writer locking";
}
