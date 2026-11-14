{ pkgs, ... }:
let
  pluginSource = pkgs.runCommandLocal "noctalia-bitwarden-plugin-source" { } ''
    mkdir -p $out
    cp -r ${./plugin} $out/bitwarden
  '';
in
{
  home-manager.users.keewai = {
    home.packages = [
      pkgs.pinentry-qt
      pkgs.rbw
    ];

    programs.noctalia.settings = {
      plugins = {
        enabled = [ "keewai/bitwarden" ];
        source = [
          {
            name = "keewai";
            kind = "path";
            location = "${pluginSource}";
            enabled = true;
          }
        ];
      };
      widget.bitwarden.type = "keewai/bitwarden:widget";
    };
  };
}
