{
  lib,
  appimageTools,
  fetchurl,
  makeWrapper,
}:

appimageTools.wrapType2 (finalAttrs: {
  pname = "helium";
  version = "0.16.5.1";

  src = fetchurl {
    url = "https://github.com/imputnet/helium-linux/releases/download/${finalAttrs.version}/helium-${finalAttrs.version}-x86_64.AppImage";
    hash = "sha256-N6+wwg46ufsbCqEJv/WpTWDCnI3tnFt58cG6TsGxXew=";
  };

  nativeBuildInputs = [ makeWrapper ];
  extraInstallCommands = ''
    install -Dm444 ${finalAttrs.contents}/helium.desktop -t $out/share/applications
    substituteInPlace $out/share/applications/helium.desktop \
      --replace-fail 'Exec=helium' "Exec=$out/bin/helium"
    install -Dm444 ${finalAttrs.contents}/helium.png -t $out/share/pixmaps

    wrapProgram $out/bin/helium \
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform=wayland --enable-wayland-ime=true --wayland-text-input-version=3}}"
  '';

  meta = {
    description = "Private Chromium-based web browser";
    homepage = "https://helium.computer/";
    license = lib.licenses.gpl3;
    mainProgram = "helium";
    platforms = [ "x86_64-linux" ];
  };
})
