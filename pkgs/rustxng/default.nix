{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  zlib,
  release,
}:
let
  info = lib.importJSON release;
  assetName = "rustxng-${info.tag_name}-x86_64-unknown-linux-gnu";
  asset = lib.findFirst (
    asset: asset.name == assetName && asset.digest != null
  ) (throw "RustXNG ${info.tag_name} has no ${assetName} asset") info.assets;
in
stdenv.mkDerivation {
  pname = "rustxng";
  version = lib.removePrefix "v" info.tag_name;
  src = fetchurl {
    url = asset.browser_download_url;
    sha256 = lib.removePrefix "sha256:" asset.digest;
  };
  dontUnpack = true;
  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [
    stdenv.cc.cc.lib
    zlib
  ];
  installPhase = ''
    runHook preInstall
    install -Dm755 "$src" "$out/bin/rustxng"
    runHook postInstall
  '';
  meta = {
    description = "SearXNG-compatible metasearch engine written in Rust";
    homepage = "https://github.com/sahenjp/RustXNG";
    license = lib.licenses.agpl3Plus;
    mainProgram = "rustxng";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
