{
  buildNpmPackage,
  fetchFromGitHub,
  fetchPnpmDeps,
  fetchurl,
  lib,
  nodejs_24,
  pnpm_10,
  pnpmConfigHook,
  stdenvNoCC,
}:

let
  packageName = "yepanywhere";
  version = "0.7.0";

  subpathClient = stdenvNoCC.mkDerivation (finalAttrs: {
    pname = "yepanywhere-subpath-client";
    inherit version;

    src = fetchFromGitHub {
      owner = "kzahel";
      repo = "yepanywhere";
      rev = "c40735b8b505844c368ea5b8f9ee4b5899116acb";
      hash = "sha256-XgElX/Aiy7otA0iWGpXcl3fGU3QK13ROY85h/cKW880=";
    };

    pnpmWorkspaces = [ "@yep-anywhere/client..." ];
    pnpmDeps = fetchPnpmDeps {
      inherit (finalAttrs)
        pname
        version
        src
        pnpmWorkspaces
        ;
      pnpm = pnpm_10;
      fetcherVersion = 3;
      hash = "sha256-AorVg545Cza+1X19TnnM3kk/IV+VNrsihgzP9daESKY=";
    };

    patches = [ ./subpath-client.patch ];

    nativeBuildInputs = [
      nodejs_24
      pnpm_10
      pnpmConfigHook
    ];

    buildPhase = ''
      runHook preBuild

      pnpm --filter @yep-anywhere/shared build
      pnpm --filter @yep-anywhere/client exec tsc
      pnpm --filter @yep-anywhere/client exec vite build --base /yep/

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p $out
      cp -r packages/client/dist/. $out/

      runHook postInstall
    '';
  });
in
buildNpmPackage {
  pname = packageName;
  inherit version;

  src = fetchurl {
    url = "https://registry.npmjs.org/${packageName}/-/${packageName}-${version}.tgz";
    hash = "sha256-FKAHC+w4s7XtCBVKH/Sk4RrL5/wtlsZRLXxplYNHZm0=";
  };

  sourceRoot = "package";
  nodejs = nodejs_24;
  npmDepsHash = "sha256-y+kK6er2qy4NKu7lCqt1Ms1f6XgZyJVZ10+5UcqXm6I=";

  patches = [ ./codex-default-provider.patch ];

  postPatch = ''
    cp ${./package-lock.json} package-lock.json
  '';

  # The npm release already contains the compiled server and web client.
  dontNpmBuild = true;

  # Build bcrypt against NixOS instead of relying on a generic prebuilt addon.
  npmRebuildFlags = [ "--build-from-source" ];

  postInstall = ''
    rm -rf $out/lib/node_modules/yepanywhere/client-dist
    mkdir -p $out/lib/node_modules/yepanywhere/client-dist
    cp -r ${subpathClient}/. $out/lib/node_modules/yepanywhere/client-dist/
  '';

  meta = {
    description = "Self-hosted browser interface for supervising coding agents";
    homepage = "https://yepanywhere.com";
    license = lib.licenses.mit;
    mainProgram = "yepanywhere";
    platforms = lib.platforms.linux;
  };
}
