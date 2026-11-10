{
  lib,
  stdenvNoCC,
  fetchurl,
  release,
}:
let
  metadata = lib.importJSON release;
  version = lib.removePrefix "wineland-" metadata.tag_name;
  assetName = "proton-wineland-${version}-x86_64_v3.tar.xz";
  asset = lib.findFirst (
    asset: asset.name == assetName && asset.digest != null
  ) (throw "No ${assetName} asset in the latest Proton Wineland release") metadata.assets;
in
stdenvNoCC.mkDerivation {
  pname = "proton-wineland";
  inherit version;
  src = fetchurl {
    url = asset.browser_download_url;
    sha256 = lib.removePrefix "sha256:" asset.digest;
  };
  dontUnpack = true;
  dontFixup = true;
  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    tar --extract --xz --file "$src" --strip-components=1 --directory "$out"
    sed -i -E 's|"proton-wineland-[^"]*"|"Proton-Wineland"|' "$out/compatibilitytool.vdf"
    runHook postInstall
  '';
  meta = {
    description = "Steam Play compatibility tool with Wayland improvements";
    homepage = "https://github.com/nanomatters/proton-salkim";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
