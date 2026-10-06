{
  lib,
  osConfig,
  pkgs,
  ...
}:
let
  scskiller =
    pkgs.runCommand "scskiller-1.2.3"
      {
        src = pkgs.fetchurl {
          url = "https://github.com/BlueHeisenberg/SCSKiller/releases/download/v1.2.3/SCSKiller-1.2.3-Portable.zip";
          sha256 = "9535f1c1fad90a30b82383a0bc8c14ee380c1549dbcff0ed24638df617fb3651";
        };
        nativeBuildInputs = [ pkgs.unzip ];
      }
      ''
        unzip -q "$src"
        mkdir -p "$out"
        cp -r current/{cli,native,notices,LICENSE,LICENSE-EXCEPTION.txt,THIRD-PARTY-NOTICES.md} "$out/"
      '';
  protontricks = pkgs.protontricks.override {
    extraCompatPaths =
      lib.makeSearchPathOutput "steamcompattool" ""
        osConfig.programs.steam.extraCompatPackages;
  };
in
{
  home.packages = [
    (pkgs.writeShellApplication {
      name = "scskiller-proton";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.steam-run
        pkgs.util-linux
        protontricks
      ];
      runtimeEnv.SCSKILLER_EXE = "${scskiller}/cli/scskiller.exe";
      text = builtins.readFile ./scskiller-proton.sh;
    })
  ];
}
