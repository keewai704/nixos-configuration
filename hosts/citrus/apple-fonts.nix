{
  pkgs,
  ...
}:
let
  srcDir = "/mnt/data/fonts/hiragino";
  fontSrc = builtins.path {
    path = srcDir;
    name = "apple-hiragino-src";
    filter = path: _type: (baseNameOf path != "lost+found");
  };
  appleHiragino = pkgs.runCommand "apple-hiragino-fonts" { } ''
    mkdir -p $out/share/fonts/hiragino
    cp ${fontSrc}/*.ttc $out/share/fonts/hiragino/
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
