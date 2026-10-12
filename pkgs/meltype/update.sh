#!/usr/bin/env nix-shell
#!nix-shell -i bash -p curl jq
set -euo pipefail
cd "$(dirname "$0")"
tag=$(curl -fsSL https://api.github.com/repos/yksr-melt/Meltype/releases/latest | jq -r .tag_name)
version=${tag#v}
url="https://github.com/yksr-melt/Meltype/releases/download/$tag/Meltype-$version-linux.zip"
release=$(nix store prefetch-file --json "$url" | jq -r .hash)
src=$(nix flake prefetch --json "github:yksr-melt/Meltype/$tag" | jq -r .hash)
jq -n --arg version "$version" --arg src "$src" --arg release "$release" \
  '{version: $version, srcHash: $src, releaseHash: $release}' > source.json
echo "Meltype $version"
