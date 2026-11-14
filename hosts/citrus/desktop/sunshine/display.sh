name=sunshine
state="${XDG_RUNTIME_DIR:?}/sunshine-disabled-outputs"
mode="${SUNSHINE_CLIENT_WIDTH:-1920}x${SUNSHINE_CLIENT_HEIGHT:-1080}@${SUNSHINE_CLIENT_FPS:-60}"

monitors() {
  hyprctl monitors all -j
}

monitor() {
  hyprctl eval "hl.monitor({ $1 })" >/dev/null
}

main_output() {
  monitors | jq -r --arg name "$name" '
    [.[] | select(.name != $name and (.disabled | not))]
    | max_by((.width / .scale) * (.height / .scale))
    | .name // empty'
}

restore() {
  if [ -f "$state" ]; then
    rm -f "$state"
    hyprctl reload >/dev/null || true
  fi
  if monitors | jq -e --arg name "$name" 'any(.[]; .name == $name)' >/dev/null; then
    hyprctl output remove "$name" >/dev/null || true
  fi
}

create() {
  restore
  hyprctl output create headless "$name" >/dev/null
  monitor "output = \"$name\", mode = \"$mode\", position = \"${1:-auto}\", scale = 1"
}

extend() {
  local main width position
  main="$(main_output)"
  width="${SUNSHINE_CLIENT_WIDTH:-1920}"
  if [ -n "$main" ]; then
    position="$(monitors | jq -r --arg main "$main" --argjson width "$width" '
      .[] | select(.name == $main)
      | "\(.x + ((.width / .scale - $width) / 2 | floor))x\(.y + (.height / .scale | floor))"')"
  fi
  create "${position:-auto}"
}

only() {
  local output
  create
  monitors | jq -r --arg name "$name" '.[] | select(.name != $name and (.disabled | not)) | .name' >"$state"
  while IFS= read -r output; do
    monitor "output = \"$output\", disabled = true"
  done <"$state"
}

case "${1:-}" in
  extend) extend ;;
  only) only ;;
  mirror | restore) restore ;;
  *)
    echo "usage: sunshine-display extend|only|mirror|restore" >&2
    exit 2
    ;;
esac
