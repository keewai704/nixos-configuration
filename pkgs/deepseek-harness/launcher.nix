{
  lib,
  writeShellApplication,
  systemd,
  curl,
  xdg-utils,
  package,
  profile,
  publicUrl,
  environment,
}:
writeShellApplication {
  name = "dsh";
  runtimeInputs = [
    systemd
    curl
    xdg-utils
  ];
  runtimeEnv = environment;
  text = ''
    profile_args=()
    if [[ ''${1:-} == web ]]; then
      shift
      profile_args=(--profile ${lib.escapeShellArg profile})
    fi

    if (( $# > 0 )) && [[ $# != 1 || $1 != --no-open ]]; then
      exec ${lib.getExe package} "''${profile_args[@]}" "$@"
    fi

    systemctl --user start dsh-web.service dsh-tailscale.service
    url=${lib.escapeShellArg publicUrl}
    curl --fail --silent --show-error --output /dev/null \
      --connect-timeout 2 --max-time 3 --retry 10 --retry-connrefused \
      --retry-delay 1 --retry-max-time 15 "$url"
    printf '%s\n' "$url"
    if (( $# == 0 )); then
      exec xdg-open "$url"
    fi
  '';
}
