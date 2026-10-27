if ! github_token=$(gh auth token --hostname github.com 2>/dev/null) || [[ -z "$github_token" ]]; then
  exec "$nix_command" "$@"
fi

netrc_file=$("$nix_command" config show netrc-file)
auth_directory=$(mktemp -d "${TMPDIR:-/tmp}/nix-github-auth.XXXXXXXXXX")
trap 'rm -rf -- "$auth_directory"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

(
  umask 077
  printf 'machine api.github.com login x-access-token password %s\n' "$github_token" > "$auth_directory/netrc"
  if [[ -r "$netrc_file" ]]; then
    cat "$netrc_file" >> "$auth_directory/netrc"
  fi
)

export NIX_CONFIG="${NIX_CONFIG:+$NIX_CONFIG$'\n'}extra-access-tokens = github.com=$github_token"$'\n'"netrc-file = $auth_directory/netrc"
unset github_token

"$nix_command" "$@"
