{
  lib,
  stdenvNoCC,
  fetchurl,
  zstd,
  steam,
  pkgsCross,
  writeShellApplication,
  symlinkJoin,
}:
let
  version = "0.2.2-beta.1";

  runner = stdenvNoCC.mkDerivation {
    pname = "wine4office-runner";
    inherit version;

    src = fetchurl {
      url = "https://github.com/ttv20/wine4office/releases/download/${version}/wine4office-${version}-x86_64.tar.zst";
      hash = "sha256-Xlhdk36xaxUSvVKaVJTFYT6A/V4G4WzzKTcWVm2V71Q=";
    };

    nativeBuildInputs = [ zstd ];
    dontConfigure = true;
    dontBuild = true;
    dontFixup = true;

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -a . "$out/"
      runHook postInstall
    '';
  };

  runtime =
    (steam.override {
      privateTmp = false;
      extraPkgs = pkgs: pkgs.wineWow64Packages.full.buildInputs;
    }).run-free;

  printer = pkgsCross.mingwW64.stdenv.mkDerivation {
    pname = "wine4office-printer";
    version = "1";
    src = ./printer.c;
    dontUnpack = true;
    dontConfigure = true;
    buildInputs = [ pkgsCross.mingwW64.windows.mcfgthreads ];
    buildPhase = ''
      runHook preBuild
      $CC -Wall -Wextra -Werror -O2 -municode -static "$src" -lwinspool -o office-printer.exe
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      install -Dm755 office-printer.exe "$out/bin/office-printer.exe"
      install -Dm644 ${./office.ppd} "$out/share/office.ppd"
      runHook postInstall
    '';
  };

  command =
    name: executable:
    writeShellApplication {
      inherit name;
      text = ''
        export WINEPREFIX="''${WINEPREFIX:-''${XDG_DATA_HOME:-$HOME/.local/share}/microsoft365/prefix}"
        export WINEARCH=win64
        export WINEDLLOVERRIDES="''${WINEDLLOVERRIDES:-winemenubuilder.exe=d;riched20=n;mshtml=b}"
        export WINEDEBUG="''${WINEDEBUG:--all}"
        export WINE_D3D_CONFIG="''${WINE_D3D_CONFIG:-renderer=gl}"
        export PATH="${runner}/bin:$PATH"
        exec ${runtime}/bin/steam-run ${runner}/bin/${executable} "$@"
      '';
    };

  wine = command "wine4office" "wine";
in
symlinkJoin {
  name = "wine4office-${version}";
  paths = [
    wine
    (command "wine4office-server" "wineserver")
    (writeShellApplication {
      name = "wine4office-setup-printer";
      text = ''
        ppd=$(${wine}/bin/wine4office winepath -w ${printer}/share/office.ppd)
        exec ${wine}/bin/wine4office ${printer}/bin/office-printer.exe "$ppd"
      '';
    })
  ];

  passthru = { inherit runner runtime; };

  meta = {
    description = "Office-focused Wine runtime in a shared FHS environment";
    homepage = "https://github.com/ttv20/wine4office";
    license = lib.licenses.lgpl21Plus;
    platforms = [ "x86_64-linux" ];
    mainProgram = "wine4office";
  };
}
