{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  deno,
  makeWrapper,
}:
let
  version = "0-unstable-2026-10-05";

  src = fetchFromGitHub {
    owner = "vrtmrz";
    repo = "livesync-bridge";
    rev = "5645cf6a74e863ccc29bc2e9dedef1c4941e096b";
    hash = "sha256-CjAU2ThV33M86mHbf+9YfIsAgPymmj9VGd+bNV7fXpc=";
  };

  deps = stdenvNoCC.mkDerivation {
    pname = "livesync-bridge-deps";
    inherit version src;

    nativeBuildInputs = [ deno ];

    buildPhase = ''
      runHook preBuild
      export HOME=$TMPDIR DENO_DIR=$TMPDIR/deno DENO_NO_UPDATE_CHECK=1
      deno install --frozen --vendor
      deno cache --frozen --vendor main.ts
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -r node_modules vendor $out/
      runHook postInstall
    '';

    dontFixup = true;
    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = "sha256-YnK8twnsu90RI91Chgn3hewtYE9jlALODNK5Jp1AZ1c=";
  };
in
stdenvNoCC.mkDerivation {
  pname = "livesync-bridge";
  inherit version src;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/livesync-bridge $out/bin
    cp -r . $out/lib/livesync-bridge/
    ln -s ${deps}/node_modules ${deps}/vendor $out/lib/livesync-bridge/
    makeWrapper ${lib.getExe deno} $out/bin/livesync-bridge \
      --set DENO_NO_UPDATE_CHECK 1 \
      --add-flags "run --cached-only --frozen --vendor -A --config $out/lib/livesync-bridge/deno.jsonc $out/lib/livesync-bridge/main.ts"
    runHook postInstall
  '';

  meta = {
    description = "Replicator between Self-hosted LiveSync remote vaults and storage";
    homepage = "https://github.com/vrtmrz/livesync-bridge";
    license = lib.licenses.unfree;
    mainProgram = "livesync-bridge";
    platforms = lib.platforms.linux;
  };
}
