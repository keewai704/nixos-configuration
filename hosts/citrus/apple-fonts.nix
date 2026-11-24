{
  pkgs,
  ...
}:
let
  srcDir = "/mnt/data/fonts/hiragino";
  appleHiragino = pkgs.runCommand "apple-hiragino-fonts" { } ''
    mkdir -p $out/share/fonts/hiragino
    cp ${srcDir}/*.ttc $out/share/fonts/hiragino/
    chmod 444 $out/share/fonts/hiragino/*.ttc
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
