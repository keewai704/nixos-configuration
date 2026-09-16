{ brave-origin }:
let
  braveOriginBase = brave-origin.override {
    commandLineArgs = "--lang=ja --accept-lang=ja-JP,ja,en-US,en";
  };
in
braveOriginBase.overrideAttrs (previous: {
  preFixup = (previous.preFixup or "") + ''
    gappsWrapperArgs+=(
      --set LANG ja_JP.UTF-8
      --set LANGUAGE ja_JP:ja
    )
  '';
})
