#!/usr/bin/env bash
set -euo pipefail

export LD_LIBRARY_PATH="/run/opengl-driver/lib:@runtimeLibraries@${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export PATH="@runtimePath@${PATH:+:$PATH}"

sourceResources="@out@/lib/chatgpt/resources"
sourceMarketplace="$sourceResources/plugins/openai-bundled"
cacheHome="${XDG_CACHE_HOME:-$HOME/.cache}"
cacheRoot="$cacheHome/chatgpt/bundled-plugin-resources/@version@-resources-v1"
marker="$cacheRoot/.source"
cachedSource=""
if [[ -L "$marker" ]]; then
  cachedSource="$(readlink "$marker")"
fi

if [[ -d "$cacheRoot" && "$cachedSource" != "$sourceResources" ]]; then
  rm -rf "$cacheRoot"
fi

if [[ "$cachedSource" != "$sourceResources" ]]; then
  cacheParent="${cacheRoot%/*}"
  mkdir -p "$cacheParent"
  staging="$(mktemp -d "$cacheParent/.@version@.XXXXXX")"
  trap 'rm -rf "$staging"' EXIT

  for resource in "$sourceResources"/*; do
    resourceName="${resource##*/}"
    if [[ "$resourceName" != plugins ]]; then
      ln -s "$resource" "$staging/$resourceName"
    fi
  done

  mkdir -p "$staging/plugins"
  cp -R "$sourceMarketplace" "$staging/plugins/openai-bundled"
  chmod -R u+rwX "$staging"
  ln -s "$sourceResources" "$staging/.source"

  if mv -T "$staging" "$cacheRoot" 2>/dev/null; then
    trap - EXIT
  fi
fi

[[ -L "$marker" && "$(readlink "$marker")" == "$sourceResources" ]]
export CODEX_ELECTRON_BUNDLED_PLUGINS_RESOURCES_PATH="$cacheRoot"

ozoneFlags=()
if [[ -n "${NIXOS_OZONE_WL:-}" && -n "${WAYLAND_DISPLAY:-}" ]]; then
  ozoneFlags=(--ozone-platform=wayland --enable-wayland-ime=true)
fi

exec "@out@/lib/chatgpt/ChatGPT" "${ozoneFlags[@]}" "$@"
