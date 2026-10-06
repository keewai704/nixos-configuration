{
  lib,
  stdenvNoCC,
  dockerTools,
  autoPatchelfHook,
  makeWrapper,
  jq,
  xz,
  fontconfig,
  freetype,
  stdenv,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "openpencil-web";
  version = "0.8.4";

  src = dockerTools.pullImage {
    imageName = "ghcr.io/zseven-w/openpencil-web";
    imageDigest = "sha256:73404ae085db8185473bbc53fe19b09bdd8d6c1f939478c50cb24aa9bbec1155";
    hash = "sha256-4OuexaEpmMXuJhspI4pSzPYzJd91BGsscMU2/YQ4skk=";
    finalImageTag = "v${finalAttrs.version}";
    os = "linux";
    arch = "amd64";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
    jq
  ];
  buildInputs = [
    xz
    fontconfig
    freetype
    stdenv.cc.cc.lib
  ];
  dontUnpack = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    mkdir image root
    tar -xf "$src" -C image
    while IFS= read -r layer; do
      tar -xf "image/$layer" -C root
    done < <(jq -r '.[0].Layers[]' image/manifest.json)
    mkdir -p "$out/bin" "$out/share/openpencil"
    cp root/app/op-host-web-server "$out/bin/"
    cp -r root/app/web-bundle "$out/share/openpencil/"
    cp ${./bootstrap.js} "$out/share/openpencil/bootstrap.js"
    cp ${./service-worker.js} "$out/share/openpencil/service-worker.js"
    wrapProgram "$out/bin/op-host-web-server" \
      --set OPENPENCIL_WEB_BUNDLE_DIR "$out/share/openpencil/web-bundle" \
      --set OPENPENCIL_CANVASKIT_DIR "$out/share/openpencil/web-bundle/canvaskit"
    runHook postInstall
  '';

  meta = {
    description = "OpenPencil web editor and HTTP MCP server";
    homepage = "https://github.com/ZSeven-W/openpencil";
    license = lib.licenses.mit;
    mainProgram = "op-host-web-server";
    platforms = [ "x86_64-linux" ];
  };
})
