{
  lib,
  symlinkJoin,
  jq,
  buildDshBundle,
  dsh-kernel,
}:
bundle:
symlinkJoin {
  name = "${bundle.pname}-kernel-${dsh-kernel.version}";
  inherit (bundle)
    pname
    version
    meta
    passthru
    ;
  paths = [ bundle ];
  postBuild = ''
    manifest="$out/lib/node_modules/${bundle.pname}/package.json"
    ${lib.getExe jq} --arg version ${lib.escapeShellArg dsh-kernel.version} '
      .peerDependencies |= with_entries(
        if (.key | startswith("@deepseek-ai/dsh-")) then .value = $version else . end
      )
    ' "$manifest" > "$manifest.tmp"
    mv "$manifest.tmp" "$manifest"
    rm "$out/nix-support/dsh-bundles.json"
    ${lib.getExe buildDshBundle.dshBundleResolver} manifest \
      "$out/nix-support/dsh-bundles.json" "$out/lib/node_modules"
  '';
}
