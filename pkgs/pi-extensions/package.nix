{
  autoPatchelfHook,
  buildNpmPackage,
  lib,
  libsecret,
  stdenv,
}:

buildNpmPackage {
  pname = "pi-extensions";
  version = "1.0.0";

  src = ./.;

  npmDepsHash = "sha256-ZAbDKjI0BfnWQleiEctlL+C7QuiW3lj6Asaqw6amdI4=";
  npmFlags = [ "--legacy-peer-deps" ];
  dontNpmBuild = true;

  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [
    libsecret
    stdenv.cc.cc.lib
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp -r node_modules "$out/lib/"

    # pi-lens 4.1.3 publishes its skills inside the package but retains the
    # monorepo-relative manifest path. Point the installed manifest at the
    # packaged directory so Pi can discover those skills from the Nix store.
    substituteInPlace "$out/lib/node_modules/pi-lens/package.json" \
      --replace-fail '"../../skills"' '"./skills"'

    # Hashline and FFF both register a tool named grep, which Pi correctly
    # rejects as ambiguous. Keep Hashline's read/replace/insert/undo tools and
    # let FFF override grep/find and provide multi_grep as requested.
    substituteInPlace "$out/lib/node_modules/pi-hashline-edit-pro/index.ts" \
      --replace-fail 'import { regGrep } from "./src/grep";' "" \
      --replace-fail '  regGrep(pi);' ""

    runHook postInstall
  '';

  meta = {
    description = "Pinned third-party extension bundle for Pi coding agent";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
