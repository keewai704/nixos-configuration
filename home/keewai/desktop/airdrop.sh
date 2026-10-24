action="${1:-receive}"
if (( $# > 0 )); then
  shift
fi

case "$action" in
  receive|send|browse) ;;
  *)
    printf 'Usage: airdrop {receive|browse|send [--to NAME] FILE...}\n' >&2
    exit 2
    ;;
esac

if [[ "$action" == send && $# == 0 ]]; then
  selection=$(zenity --file-selection --multiple --separator=$'\n' --title='Send via AirDrop') || exit
  mapfile -t files <<< "$selection"
  set -- "${files[@]}"
fi

exec 9>"$XDG_RUNTIME_DIR/airdrop.lock"
if ! flock -n 9; then
  printf 'Another AirDrop window is using the radio. Close it first.\n' >&2
  exit 1
fi

owly radio up &
radio_pid=$!
cleanup() {
  kill -TERM "$radio_pid" 2>/dev/null || true
  wait "$radio_pid" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP

ready=false
for (( attempt=0; attempt<300; attempt++ )); do
  if ! kill -0 "$radio_pid" 2>/dev/null; then
    wait "$radio_pid"
    exit 1
  fi
  if ip -6 -o address show dev awdl0 scope link 2>/dev/null | grep -qv tentative; then
    ready=true
    break
  fi
  sleep 0.1
done
if [[ "$ready" != true ]]; then
  printf 'AirDrop radio did not become ready. Run owly doctor for details.\n' >&2
  exit 1
fi

case "$action" in
  receive)
    destination="$(xdg-user-dir DOWNLOAD)/AirDrop"
    mkdir -p "$destination"
    printf 'On the Apple device, enable AirDrop for Everyone for 10 Minutes.\nSelect this computer from the share sheet and accept the request here.\nReceived files: %s\nClose this window to stop receiving.\n' "$destination"
    owly receive --dir "$destination" "$@"
    ;;
  browse)
    owly browse "$@"
    ;;
  send)
    if [[ "${1:-}" != --to ]]; then
      printf 'Unlock the Apple device, enable AirDrop for Everyone for 10 Minutes, and close its share sheet.\n'
      owly browse
      read -r -p 'Receiver name: ' receiver
      if [[ -z "$receiver" ]]; then
        exit 1
      fi
      set -- --to "$receiver" "$@"
    fi
    owly send "$@"
    ;;
esac
