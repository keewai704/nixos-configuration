{
  config,
  lib,
  pkgs,
  ...
}:
let
  appImage = "${config.xdg.dataHome}/siora/Siora-x86_64.AppImage";

  sioraUpdate = pkgs.writeShellApplication {
    name = "siora-update";
    runtimeInputs = with pkgs; [
      coreutils
      gh
    ];
    text = ''
      appimage=${lib.escapeShellArg appImage}
      asset=$(basename "$appimage")
      digest=$(gh release view -R keewai704/siora --json assets \
        --jq ".assets[] | select(.name == \"$asset\") | .digest")
      if [ -z "$digest" ]; then
        echo "siora-update: the latest release has no $asset" >&2
        exit 1
      fi
      if [ -x "$appimage" ] && [ "sha256:$(sha256sum "$appimage" | cut -d' ' -f1)" = "$digest" ]; then
        exit 0
      fi
      mkdir -p "$(dirname "$appimage")"
      tmp=$(mktemp "$appimage.XXXXXX")
      trap 'rm -f "$tmp"' EXIT
      gh release download -R keewai704/siora -p "$asset" -O "$tmp" --clobber
      if [ "sha256:$(sha256sum "$tmp" | cut -d' ' -f1)" != "$digest" ]; then
        echo "siora-update: $asset does not match $digest" >&2
        exit 1
      fi
      chmod 755 "$tmp"
      mv "$tmp" "$appimage"
    '';
  };

  siora = pkgs.writeShellApplication {
    name = "siora";
    runtimeInputs = with pkgs; [
      mpv-unwrapped
      ffmpeg-headless
      sioraUpdate
    ];
    text = ''
      appimage=${lib.escapeShellArg appImage}
      [ -x "$appimage" ] || siora-update
      exec "$appimage" "$@"
    '';
  };
in
{
  home.packages = [
    siora
    sioraUpdate
  ];

  home.activation.updateSiora = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${pkgs.coreutils}/bin/timeout 600 ${lib.getExe sioraUpdate} \
      || warnEcho "Could not update the Siora AppImage; keeping the current one"
  '';

  xdg.desktopEntries.siora = {
    name = "Siora";
    comment = "Native Apple Music client";
    exec = "siora";
    icon = "siora";
    terminal = false;
    categories = [
      "AudioVideo"
      "Audio"
      "Player"
    ];
  };

  xdg.dataFile = {
    "icons/hicolor/scalable/apps/siora.svg".text = lib.replaceStrings [ "currentColor" ] [ "#ff5d7a" ] (
      builtins.readFile ./siora.svg
    );
    "icons/hicolor/symbolic/apps/siora-symbolic.svg".source = ./siora.svg;
  };
}
