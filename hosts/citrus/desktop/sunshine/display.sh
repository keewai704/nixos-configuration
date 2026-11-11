name=sunshine
state="${XDG_RUNTIME_DIR:?}/sunshine-disabled-outputs"

outputs() {
  umbriel outputs --json
}

main_output() {
  outputs | jq -r --arg name "$name" '
    [.[] | select(.name != $name and .enabled)]
    | max_by(.logical_size.width * .logical_size.height)
    | .name // empty'
}

evacuate() {
  local target workspace id
  target="$(main_output)"
  [ -n "$target" ] || return 0
  workspace="$(umbriel workspaces --json |
    jq -r --arg out "$target" '.[] | select(.output == $out and .active) | .index' | head -n 1)"
  [ -n "$workspace" ] || return 0
  for id in $(umbriel windows --json | jq -r --arg out "$name" '.[] | select(.output == $out) | .id'); do
    umbriel msg window-focus "$id" >/dev/null
    umbriel msg window-move-to-workspace-silent "$workspace" --output "$target" >/dev/null
  done
}

restore() {
  local output
  if [ -f "$state" ]; then
    while IFS= read -r output; do
      umbriel msg output-enable "$output" >/dev/null || true
    done <"$state"
    rm -f "$state"
  fi
  if outputs | jq -e --arg name "$name" 'any(.[]; .name == $name)' >/dev/null; then
    evacuate || true
    umbriel output-destroy "$name" >/dev/null || true
  fi
}

create() {
  restore
  umbriel output-create "$name" \
    "${SUNSHINE_CLIENT_WIDTH:-1920}x${SUNSHINE_CLIENT_HEIGHT:-1080}@${SUNSHINE_CLIENT_FPS:-60}" >/dev/null
}

extend() {
  local main position
  main="$(main_output)"
  create
  [ -n "$main" ] || return 0
  position="$(outputs | jq -r --arg name "$name" --arg main "$main" '
    (.[] | select(.name == $name)) as $virtual
    | (.[] | select(.name == $main)) as $main
    | "\($main.position.x + (($main.logical_size.width - $virtual.logical_size.width) / 2 | floor)),\($main.position.y + $main.logical_size.height)"')"
  wlr-randr --output "$name" --pos "$position"
}

only() {
  local output
  create
  outputs | jq -r --arg name "$name" '.[] | select(.name != $name and .enabled) | .name' >"$state"
  while IFS= read -r output; do
    umbriel msg output-disable "$output" >/dev/null
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
