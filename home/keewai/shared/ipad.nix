{ lib, pkgs, ... }:

{

  # Typer's native completion protocol; run Python only when completing.
  programs.zsh.siteFunctions._pymobiledevice3 = ''
    #compdef pymobiledevice3
    eval "$(env _TYPER_COMPLETE_ARGS="''${words[1,$CURRENT]}" _PYMOBILEDEVICE3_COMPLETE=complete_zsh pymobiledevice3)"
  '';

  # Nixpkgs 7.7.0 lacks CoreDevice touch input and has a broken pyimg4 dependency.
  home.packages = [
    (pkgs.writeShellApplication {
      name = "pymobiledevice3";
      runtimeInputs = [ pkgs.stdenv.cc ]; # lzfse needs a compiler on first install.
      text = ''
        export LD_LIBRARY_PATH="${
          lib.makeLibraryPath [
            pkgs.stdenv.cc.cc.lib
            pkgs.zlib
            pkgs.libusb1
          ]
        }''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
        export UV_PYTHON_DOWNLOADS=never
        exec ${lib.getExe pkgs.uv} tool run \
          --python ${pkgs.python313}/bin/python3 \
          --from pymobiledevice3==11.5.0 pymobiledevice3 "$@"
      '';
    })
  ];
}
