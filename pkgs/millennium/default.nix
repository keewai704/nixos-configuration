{
  callPackage,
  stdenv,
  upstream,
}:
callPackage "${upstream}/millennium.nix" {
  millennium-src = upstream.inputs.millennium-src;
  inherit (upstream.inputs.nixpkgs-bun.legacyPackages.${stdenv.hostPlatform.system}) bun;
}
