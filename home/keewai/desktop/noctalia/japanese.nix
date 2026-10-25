{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  upstream = builtins.fromJSON (builtins.readFile "${inputs.noctalia}/assets/translations/ja.json");
  supplement = builtins.fromJSON (builtins.readFile ./ja.json);
  catalog = pkgs.writeText "noctalia-ja.json" (
    builtins.toJSON (lib.recursiveUpdate supplement upstream)
  );
  assets = pkgs.symlinkJoin {
    name = "noctalia-japanese-assets";
    paths = [ "${config.programs.noctalia.package}/share/noctalia/assets" ];
    postBuild = ''
      rm "$out/translations/ja.json"
      ln -s ${catalog} "$out/translations/ja.json"
    '';
  };
in
{
  programs.noctalia.settings.shell.lang = "ja";
  systemd.user.services.noctalia.Service.Environment = [ "NOCTALIA_ASSETS_DIR=${assets}" ];
}
