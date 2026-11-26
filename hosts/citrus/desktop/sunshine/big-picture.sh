case "${1:-}" in
  open) setsid -f steam steam://open/bigpicture >/dev/null 2>&1 ;;
  close)
    if pgrep -x steam >/dev/null; then
      steam steam://close/bigpicture >/dev/null 2>&1 || true
    fi
    ;;
  *)
    echo "usage: sunshine-big-picture open|close" >&2
    exit 2
    ;;
esac
