{
  lib,
  writeShellApplication,
  python3,
  umbriel,
  wlr-randr,
}:
writeShellApplication {
  name = "sunshine-display";
  runtimeInputs = [
    umbriel
    wlr-randr
  ];
  text = ''
    exec ${lib.getExe python3} ${./sunshine-display.py} "$@"
  '';
}
