{ lib, pkgs }:
{
  name,
  command,
  runtimeInputs ? [ ],
}:
pkgs.writeShellApplication {
  inherit name;
  runtimeInputs = [ pkgs.stdenv.cc ] ++ runtimeInputs;
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
      --from pymobiledevice3==11.15.5 ${command} "$@"
  '';
}
