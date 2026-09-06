{ lib, pkgs, ... }:

{
  services.usbmuxd.enable = true;

  # Nixpkgs 7.7.0 lacks CoreDevice touch input and has a broken pyimg4 dependency.
  environment.systemPackages = [
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
          --from pymobiledevice3==11.4.2 pymobiledevice3 "$@"
      '';
    })
  ];
}
