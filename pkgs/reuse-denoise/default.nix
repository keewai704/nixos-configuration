{
  lib,
  fetchurl,
  python3Packages,
  runCommandCC,
  writers,
  upstream,
}:
let
  pointer = lib.splitString "\n" (builtins.readFile (upstream + "/model.safetensors"));
  oid =
    lib.findFirst (lib.hasPrefix "oid sha256:") (throw "RE-USE weights are not an LFS pointer")
      pointer;
  weights = fetchurl {
    url = "https://huggingface.co/nvidia/NVIDIA-NemotronLabs-RE-USE/resolve/${upstream.rev}/model.safetensors";
    sha256 = lib.removePrefix "oid sha256:" oid;
  };
  scan = runCommandCC "reuse-selective-scan" { } ''
    mkdir -p $out/lib
    $CC -O3 -ffast-math -fopenmp -shared -fPIC ${./selective-scan.c} -o $out/lib/libselective-scan.so -lm
  '';
in
writers.writePython3Bin "reuse-denoise"
  {
    libraries = with python3Packages; [
      av
      einops
      huggingface-hub
      numpy
      safetensors
      torch
    ];
    flakeIgnore = [ "E501" ];
  }
  (
    lib.replaceStrings
      [ "@upstream@" "@weights@" "@scan@" ]
      [ "${upstream}" "${weights}" "${scan}/lib/libselective-scan.so" ]
      (builtins.readFile ./reuse-denoise.py)
  )
