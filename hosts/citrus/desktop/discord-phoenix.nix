{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  src = inputs.discord-phoenix.outPath;

  loader = pkgs.runCommand "sunbird-loader" { } ''
    install -Dm755 ${inputs.sunbird-loader} $out/lib/libphoenix.so
  '';

  fontsConf = pkgs.writeText "discord-phoenix-fonts.conf" ''
    <?xml version="1.0"?>
    <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
    <fontconfig>
      <dir prefix="xdg">fonts</dir>
    ${
      lib.concatMapStrings (font: "  <dir>${font}</dir>\n") (
        lib.filter (font: !lib.hasPrefix "noto-fonts-cjk-" font.name) (lib.unique config.fonts.packages)
      )
    }</fontconfig>
  '';

  contents = pkgs.appimageTools.extract {
    pname = "discord-phoenix";
    version = "2233";
    inherit src;
  };

  discordPhoenix = pkgs.appimageTools.wrapType2 {
    pname = "discord-phoenix";
    version = "2233";
    inherit src;

    profile = ''
      export FONTCONFIG_FILE=${fontsConf}
      export LD_PRELOAD="${loader}/lib/libphoenix.so''${LD_PRELOAD:+:$LD_PRELOAD}"
    '';

    extraInstallCommands = ''
      install -Dm644 ${contents}/com.discord.libdiscord.desktop -t $out/share/applications
      cp -r ${contents}/usr/share/icons $out/share/icons
    '';

    meta = {
      mainProgram = "discord-phoenix";
      platforms = [ "x86_64-linux" ];
      license = lib.licenses.unfree;
    };
  };
in
{
  home-manager.users.keewai.home.packages = [ discordPhoenix ];
}
