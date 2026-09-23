{
  lib,
  writeShellApplication,
  python3,
  hyprland,
}:
writeShellApplication {
  name = "sunshine-display";
  runtimeInputs = [ hyprland ];
  text = ''
    exec ${lib.getExe python3} ${./sunshine-display.py} "$@"
  '';
}
