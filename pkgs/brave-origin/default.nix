{
  lib,
  brave-origin,
  fetchurl,
}:
let
  braveOriginVersion = "1.94.121";
  braveOriginBase = brave-origin.override {
    commandLineArgs = "--lang=ja --accept-lang=ja-JP,ja,en-US,en";
  };
  braveOriginCurrent =
    if lib.versionAtLeast braveOriginBase.version braveOriginVersion then
      braveOriginBase
    else
      braveOriginBase.overrideAttrs (_: {
        version = braveOriginVersion;
        src = fetchurl {
          url = "https://github.com/brave/brave-browser/releases/download/v${braveOriginVersion}/brave-origin_${braveOriginVersion}_amd64.deb";
          hash = "sha256-D3bsXwBBOVQ1XBmw1mM7YYrEQYr+0zPhTs6YDGtrFJU=";
        };
      });
  braveOrigin = braveOriginCurrent.overrideAttrs (previous: {
    preFixup = (previous.preFixup or "") + ''
      gappsWrapperArgs+=(
        --set LANG ja_JP.UTF-8
        --set LANGUAGE ja_JP:ja
      )
    '';
  });

in
braveOrigin
