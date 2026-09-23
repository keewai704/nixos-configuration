{
  lib,
  buildNpmPackage,
  fetchurl,
}:
let
  manifest = builtins.fromJSON (builtins.readFile ./package.json);
  codeModeHost = fetchurl {
    url = "https://github.com/openai/codex/releases/download/rust-v0.145.0/codex-code-mode-host-x86_64-unknown-linux-musl.tar.gz";
    hash = "sha256-rCMXeVbDDMH58YDCe9gPW7W3Z4DbVfuU3MImRNSQhS4=";
  };
in
buildNpmPackage {
  pname = "pi-codex-conversion";
  version = manifest.dependencies."@howaboua/pi-codex-conversion";
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./package.json
      ./package-lock.json
    ];
  };
  npmDepsHash = "sha256-7XuCqCEvbLm4Wn3fFHMTXMi1paHxM5ubgYhvxDSdoTY=";
  npmFlags = [
    "--ignore-scripts"
    "--legacy-peer-deps"
  ];
  dontNpmBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib"
    cp -r node_modules "$out/lib/"
    host_dir="$out/lib/node_modules/@howaboua/pi-codex-conversion/code-mode/bin/linux-x64"
    mkdir -p "$host_dir"
    tar -xzf ${codeModeHost} -C "$host_dir"
    mv "$host_dir/codex-code-mode-host-x86_64-unknown-linux-musl" "$host_dir/codex-code-mode-host"
    runHook postInstall
  '';

  meta = {
    description = "Pi Codex conversion extension with pinned runtime dependencies";
    homepage = "https://github.com/IgorWarzocha/howaboua-pi-stuff/tree/main/packages/pi-codex-conversion";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
  };
}
