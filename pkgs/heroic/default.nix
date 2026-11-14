{ heroic, heroic-unwrapped }:
let
  patched = heroic-unwrapped.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      substituteInPlace $out/bin/heroic --replace-fail ' --disable-gpu-compositing ' ' '
    '';
  });
in
heroic.override { heroic-unwrapped = patched; }
