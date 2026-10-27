{
  lib,
  stdenv,
  stdenvNoCC,
  callPackage,
  python313,
  autoPatchelfHook,
  makeWrapper,
  unzip,
  openssl,
  zlib,
  libdrm,
  libva,
  libx11,
  libvdpau,
  ocl-icd,
  numactl,
  libcap,
  systemd,
  upstream,
  thirdparty,
  inputs,
}:
let
  workspace = inputs.uv2nix.lib.workspace.loadWorkspace {
    workspaceRoot = upstream + "/server";
  };
  pythonSet =
    (callPackage inputs.pyproject-nix.build.packages { python = python313; }).overrideScope
      (
        lib.composeManyExtensions [
          inputs.pyproject-build-systems.overlays.wheel
          (workspace.mkPyprojectOverlay { sourcePreference = "wheel"; })
          (final: previous: {
            elevate = previous.elevate.overrideAttrs (old: {
              nativeBuildInputs =
                (old.nativeBuildInputs or [ ]) ++ final.resolveBuildSystem { setuptools = [ ]; };
            });
            grapheme = previous.grapheme.overrideAttrs (old: {
              nativeBuildInputs =
                (old.nativeBuildInputs or [ ]) ++ final.resolveBuildSystem { setuptools = [ ]; };
            });
          })
        ]
      );
  pythonEnv = pythonSet.mkVirtualEnv "konomitv-python" workspace.deps.default;
  binaries = stdenv.mkDerivation {
    pname = "konomitv-thirdparty";
    version = upstream.shortRev;
    src = thirdparty;
    sourceRoot = ".";
    unpackPhase = ''
      unzip -p "$src" thirdparty-linux.tar.xz | tar -xJ --exclude='thirdparty/Python' --exclude='thirdparty/NVEncC' --exclude='thirdparty/VCEEncC' --exclude='thirdparty/rkmppenc' --exclude='thirdparty/Akebi'
    '';
    nativeBuildInputs = [
      autoPatchelfHook
      makeWrapper
      unzip
    ];
    buildInputs = [
      stdenv.cc.cc.lib
      openssl
      zlib
      libdrm
      libva
      libx11
      libvdpau
      ocl-icd
      numactl
      libcap
      systemd
    ];
    installPhase = ''
      mkdir -p "$out"
      cp -R thirdparty/. "$out/"
    '';
    preFixup = ''
      addAutoPatchelfSearchPath "$out"
    '';
  };
in
stdenvNoCC.mkDerivation {
  pname = "konomitv";
  version = "0.14.1-${upstream.shortRev}";
  src = upstream;
  nativeBuildInputs = [
    python313
    makeWrapper
  ];
  postPatch = ''
    python ${./edcb.py} .
    python ${./playback.py} .
    python ${./subpath.py} .
    substituteInPlace server/app/constants.py \
      --replace-fail "DATA_DIR = BASE_DIR / 'data'" "DATA_DIR = Path('/var/lib/konomitv/data')" \
      --replace-fail "LOGS_DIR = BASE_DIR / 'logs'" "LOGS_DIR = Path('/var/log/konomitv')"
    substituteInPlace server/app/config.py \
      --replace-fail "_CONFIG_YAML_PATH = BASE_DIR.parent / 'config.yaml'" "_CONFIG_YAML_PATH = Path('/var/lib/konomitv/config.yaml')"
  '';
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/share/konomitv" "$out/bin"
    cp -R server client "$out/share/konomitv/"
    rm -r "$out/share/konomitv/server/thirdparty"
    ln -s ${binaries} "$out/share/konomitv/server/thirdparty"
    makeWrapper ${pythonEnv}/bin/python "$out/bin/konomitv" \
      --chdir "$out/share/konomitv/server" \
      --set PYTHONUNBUFFERED 1 \
      --add-flags "$out/share/konomitv/server/KonomiTV.py"
    runHook postInstall
  '';
  passthru = { inherit pythonEnv binaries; };
  meta = {
    description = "KonomiTV media server with a loopback HTTP listener and /tv mount";
    homepage = "https://github.com/tsukumijima/KonomiTV";
    license = lib.licenses.mit;
    mainProgram = "konomitv";
    platforms = [ "x86_64-linux" ];
  };
}
