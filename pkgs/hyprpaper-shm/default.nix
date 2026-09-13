{
  fetchFromGitHub,
  hyprland,
  hyprpaper,
  lib,
  python3,
  stdenvNoCC,
}:

let
  source = fetchFromGitHub {
    owner = "hyprwm";
    repo = "hyprpaper";
    tag = "v0.7.6";
    sha256 = "1g9d2yp5gsyv6b0gvvw6dz9f97nqqs34pbmkwdpvb75zi8rv3wwp";
  };

  hyprctl = stdenvNoCC.mkDerivation {
    pname = "hyprctl-hyprpaper-legacy";
    version = "0.7.6";
    dontUnpack = true;
    dontConfigure = true;
    dontBuild = true;
    doCheck = true;

    checkPhase = ''
      cp ${./hyprctl.py} "$TMPDIR/hyprctl.py"
      cp ${./test_hyprctl.py} "$TMPDIR/test_hyprctl.py"
      ${python3}/bin/python3 "$TMPDIR/test_hyprctl.py"
    '';

    installPhase = ''
      install -Dm755 ${./hyprctl.py} "$out/bin/hyprctl"
      substituteInPlace "$out/bin/hyprctl" \
        --replace-fail '@PYTHON@' '${python3}/bin/python3' \
        --replace-fail '@REAL_HYPRCTL@' '${hyprland}/bin/hyprctl'
    '';

    meta = {
      description = "Legacy hyprpaper IPC bridge for the Hyper-V VM";
      mainProgram = "hyprctl";
      platforms = lib.platforms.linux;
    };
  };
in
hyprpaper.overrideAttrs (old: {
  version = "0.7.6";
  src = source;
  passthru = (old.passthru or { }) // {
    inherit hyprctl;
  };
})
