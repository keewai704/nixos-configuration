{
  inputs,
  pkgs,
  ...
}:
let
  appleHiragino = pkgs.runCommand "apple-hiragino-fonts" { } ''
    mkdir -p $out/share/fonts/hiragino
    cp ${inputs.hiragino-fonts}/*.ttc $out/share/fonts/hiragino/
  '';
in
{
  fonts.packages = [ appleHiragino ];
  fonts.fontconfig.defaultFonts = {
    sansSerif = [
      "Hiragino Sans"
      "DejaVu Sans"
    ];
    serif = [
      "Hiragino Mincho ProN"
      "DejaVu Serif"
    ];
  };
}
