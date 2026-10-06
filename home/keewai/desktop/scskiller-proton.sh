#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scskiller-proton APPID [--threads N] [--idle] [--careful | --fast]
       scskiller-proton APPID --status
       scskiller-proton APPID --dry-run

Compile shaders with SCSKiller using the game's Steam-selected Proton and prefix.
Start the game through Steam once before using this command, then close it.

  --status   Show SCSKiller's game status without compiling.
  --dry-run  Scan the game and show the cache paths and command without compiling.
  --help     Show this help.

Steam shader pre-caching must be enabled to reuse the per-game driver cache.
Custom cache paths and GPU settings must match the game's launch environment;
export the same variables here. STEAM_DIR and PROTON_VERSION are also honored.
For a persistent VKD3D translation cache, set VKD3D_SHADER_CACHE_PATH to the same
directory in Steam's launch options and here. Otherwise its cache is temporary;
the GPU driver cache still persists in Steam's shadercache directory.

SCSKiller targets Windows; Proton cache coverage is experimental and depends on
the game, GPU and driver. Games requiring an AES key or a recording must first
be prepared in SCSKiller. This command does not install a recorder.
EOF
}

die() {
  printf 'scskiller-proton: %s\n' "$*" >&2
  exit 1
}

if [[ ${1:-} == --help || ${1:-} == -h ]]; then
  usage
  exit 0
fi
if [[ ! ${1:-} =~ ^[1-9][0-9]*$ ]]; then
  usage >&2
  exit 2
fi

original_args=("$@")
appid=$1
shift
mode=compile
compile_args=()
while (($#)); do
  case $1 in
    --status | --dry-run)
      [[ $mode == compile && ${#compile_args[@]} == 0 && $# == 1 ]] || die "Use --status or --dry-run on its own."
      mode=${1#--}
      shift
      ;;
    --threads)
      [[ ${2:-} =~ ^[1-9][0-9]*$ ]] || die "--threads needs a positive integer."
      compile_args+=("$1" "$2")
      shift 2
      ;;
    --idle | --careful | --fast)
      compile_args+=("$1")
      shift
      ;;
    *) die "Unknown option: $1 (see --help)." ;;
  esac
done

if [[ ${SCSKILLER_PROTON_STAGE:-} != "$appid" ]]; then
  printf -v command '%q ' steam-run "$BASH" "$(readlink -f "$0")" "${original_args[@]}"
  export SCSKILLER_PROTON_STAGE=$appid
  exec protontricks -c "exec $command" "$appid"
fi

[[ ${STEAM_APPID:-} == "$appid" && -d ${WINEPREFIX:-}/drive_c && -d ${STEAM_APP_PATH:-} ]] ||
  die "Protontricks did not provide an initialized game prefix and install directory."
[[ -f $SCSKILLER_EXE && -n ${PROTON_PATH:-} ]] || die "SCSKiller or Proton is missing."
PATH="$(dirname "$WINE_BIN"):$PATH"
export PATH
export WINE="$WINE_BIN" WINELOADER="$WINE_BIN" WINESERVER="$WINESERVER_BIN"

steamapps=$(dirname "$STEAM_APP_PATH")
while [[ $steamapps != / && ! -f $steamapps/appmanifest_$appid.acf ]]; do
  steamapps=$(dirname "$steamapps")
done
[[ -f $steamapps/appmanifest_$appid.acf ]] || die "Cannot locate appmanifest_$appid.acf for $STEAM_APP_PATH."

exec 9>"${WINEPREFIX%/pfx}/scskiller-proton.lock"
flock -n 9 || die "SCSKiller is already running for appid $appid."

export SteamAppId=$appid SteamGameId=$appid
export STEAM_COMPAT_SHADER_PATH=${STEAM_COMPAT_SHADER_PATH:-$steamapps/shadercache/$appid}
export __GL_SHADER_DISK_CACHE=${__GL_SHADER_DISK_CACHE:-1}
export __GL_SHADER_DISK_CACHE_PATH=${__GL_SHADER_DISK_CACHE_PATH:-$STEAM_COMPAT_SHADER_PATH/nvidiav1}
export __GL_SHADER_DISK_CACHE_APP_NAME=${__GL_SHADER_DISK_CACHE_APP_NAME:-steamapp_shader_cache}
export MESA_SHADER_CACHE_DIR=${MESA_SHADER_CACHE_DIR:-$STEAM_COMPAT_SHADER_PATH}
export MESA_DISK_CACHE_SINGLE_FILE=${MESA_DISK_CACHE_SINGLE_FILE:-1}
export DXVK_STATE_CACHE_PATH=${DXVK_STATE_CACHE_PATH:-$STEAM_COMPAT_SHADER_PATH/DXVK_state_cache}
export WINEDEBUG=${WINEDEBUG:--all}
export DXVK_LOG_LEVEL=${DXVK_LOG_LEVEL:-error}
export VKD3D_DEBUG=${VKD3D_DEBUG:-err}

printf 'Proton: %s\nPrefix: %s\n' "$PROTON_PATH" "$WINEPREFIX"
wineserver -p60 9>&-
wine "$SCSKILLER_EXE" status "steam:$appid" 9>&-
[[ $mode != status ]] || exit 0

printf 'NVIDIA cache: %s\nMesa cache: %s\nDXVK cache: %s\nVKD3D cache: %s\n' \
  "$__GL_SHADER_DISK_CACHE_PATH" "$MESA_SHADER_CACHE_DIR" "$DXVK_STATE_CACHE_PATH" "${VKD3D_SHADER_CACHE_PATH:-temporary}"
printf 'Command: '
printf '%q ' wine "$SCSKILLER_EXE" compile "steam:$appid" "${compile_args[@]}"
printf '\n'
[[ $mode != dry-run ]] || exit 0

mkdir -p "$__GL_SHADER_DISK_CACHE_PATH" "$MESA_SHADER_CACHE_DIR" "$DXVK_STATE_CACHE_PATH"
if [[ -n ${VKD3D_SHADER_CACHE_PATH:-} && $VKD3D_SHADER_CACHE_PATH != 0 ]]; then
  mkdir -p "$VKD3D_SHADER_CACHE_PATH"
fi

wine "$SCSKILLER_EXE" compile "steam:$appid" "${compile_args[@]}" 9>&-
