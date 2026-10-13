{
  lib,
  writeShellApplication,
  systemd,
  curl,
  coreutils,
  gnused,
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
    coreutils
    gnused
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
    base_url=${lib.escapeShellArg publicUrl}
    url=
    for (( attempt = 0; attempt < 30; attempt++ )); do
      invocation=$(systemctl --user show dsh-web.service --property=InvocationID --value)
      url=$(journalctl --user -u dsh-web.service "_SYSTEMD_INVOCATION_ID=$invocation" \
        --output=cat --no-pager | sed -n 's/^dsh web: //p' | tail -n 1)
      if [[ $url == "$base_url?token="* ]]; then
        break
      fi
      sleep 0.5
    done
    if [[ $url != "$base_url?token="* ]]; then
      printf '%s\n' 'dsh: the web service did not provide an authenticated URL; check journalctl --user -u dsh-web.service' >&2
      exit 1
    fi
    curl --fail --silent --show-error --output /dev/null \
      --connect-timeout 2 --max-time 3 --retry 10 --retry-connrefused \
      --retry-delay 1 --retry-max-time 15 "$url"
    printf '%s\n' "$url"
    if (( $# == 0 )); then
      exec xdg-open "$url"
    fi
  '';
}
