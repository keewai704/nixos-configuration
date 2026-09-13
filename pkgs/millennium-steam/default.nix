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
  source = builtins.readFile "${millennium}/millennium.nix";
  from = [
    "bun install --frozen-lockfile"
    "bun node_modules/.bin/rollup -c"
    "mkdir -p $out\n"
    "sha256-iPdEl5GH0cXjn1EUdYutqxdMwdRXms+eXCEIwZ3xeLY="
  ];
  to = [
    "bun install --linker hoisted --frozen-lockfile"
    "bun ../node_modules/.bin/rollup -c"
    "mkdir -p $out\n      find src/typescript -name node_modules -prune -o -name package.json -exec cp --parents -t $out {} +\n"
    "sha256-uI0hNSmMezYRPUu17KAzlkYZ/n9Cz2UnP7cefWyi+pU="
  ];
  fixedMillennium = pkgs.callPackage (builtins.toFile "millennium-hoisted.nix" (
    builtins.replaceStrings from to source
  )) { millennium-src = millennium.inputs.millennium-src; };
in
assert lib.assertMsg (lib.all (
  text: lib.hasInfix text source
) from) "Millennium's upstream recipe changed; review the hoisted dependency patch";
pkgs.callPackage "${millennium}/steam.nix" { millennium = fixedMillennium; }
