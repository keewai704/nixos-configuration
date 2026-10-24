{
  callPackage,
  lib,
  stdenv,
  upstream,
}:
let
  recipe = builtins.toFile "millennium.nix" (
    lib.replaceStrings
      [ "sha256-o0wv6vG1YZR9TcgytD9CDf8zBei4Ulhl59Mo9C6C+vs=" ]
      [ "sha256-WdqZqCAXzs7O+SnGD3U9cLnyBSv9psBAamY++/2dIJg=" ]
      (builtins.readFile "${upstream}/millennium.nix")
  );
in
callPackage recipe {
  millennium-src = upstream.inputs.millennium-src;
  inherit (upstream.inputs.nixpkgs-bun.legacyPackages.${stdenv.hostPlatform.system}) bun;
}
