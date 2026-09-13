{
  lib,
  stdenv,
  millennium,
}:
let
  pkgs = import millennium.inputs.nixpkgs {
    system = stdenv.hostPlatform.system;
    config.allowUnfree = true;
  };
  upstreamRecipe = builtins.readFile "${millennium}/millennium.nix";
  dependencyPatches = [
    {
      original = "bun install --frozen-lockfile";
      replacement = "bun install --linker hoisted --frozen-lockfile";
    }
    {
      original = "bun node_modules/.bin/rollup -c";
      replacement = "bun ../node_modules/.bin/rollup -c";
    }
    {
      original = "mkdir -p $out\n";
      replacement = "mkdir -p $out\n      find src/typescript -name node_modules -prune -o -name package.json -exec cp --parents -t $out {} +\n";
    }
    {
      original = "sha256-iPdEl5GH0cXjn1EUdYutqxdMwdRXms+eXCEIwZ3xeLY=";
      replacement = "sha256-uI0hNSmMezYRPUu17KAzlkYZ/n9Cz2UnP7cefWyi+pU=";
    }
  ];
  originalFragments = map (patch: patch.original) dependencyPatches;
  replacementFragments = map (patch: patch.replacement) dependencyPatches;
  fixedMillennium = pkgs.callPackage (builtins.toFile "millennium-hoisted.nix" (
    builtins.replaceStrings originalFragments replacementFragments upstreamRecipe
  )) { millennium-src = millennium.inputs.millennium-src; };
in
assert lib.assertMsg (lib.all (
  text: lib.hasInfix text upstreamRecipe
) originalFragments) "Millennium's upstream recipe changed; review the hoisted dependency patch";
pkgs.callPackage "${millennium}/steam.nix" { millennium = fixedMillennium; }
