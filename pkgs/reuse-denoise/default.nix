{
  fetchurl,
  ffmpeg-headless,
  lib,
  python3,
  runCommand,
  writeShellApplication,
  upstream,
  mambaSrc,
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
  repository = "models--nvidia--NVIDIA-NemotronLabs-RE-USE";
  hubCache = runCommand "reuse-hub-cache" { } ''
    snapshot=$out/${repository}/snapshots/${upstream.rev}
    mkdir -p "$snapshot" $out/${repository}/refs
    printf %s ${upstream.rev} > $out/${repository}/refs/main
    ln -s ${upstream}/config.json "$snapshot/config.json"
    ln -s ${weights} "$snapshot/model.safetensors"
  '';
  python = python3.withPackages (
    ps: with ps; [
      einops
      huggingface-hub
      librosa
      (mamba-ssm.overridePythonAttrs (old: {
        src = mambaSrc;
        pname = "mamba-ssm";
        version = "unstable-${mambaSrc.shortRev}";
        pythonRemoveDeps = [
          "apache-tvm-ffi"
          "quack-kernels"
          "tilelang"
        ];
        postPatch = (old.postPatch or "") + ''
          sed -i "s/c++17/c++20/g" setup.py
        '';
        env = old.env // {
          MAMBA_KEEP_CUDA_BUILD = "TRUE";
        };
      }))
      pyyaml
      resampy
      safetensors
      torch
      torchaudio
      torchcodec
    ]
  );
  recipe = "USEMamba_30x1_lr_00002_norm_05_vq_065_nfft_320_hop_40_NRIR_012_pha_0005_com_04_early_001.yaml";
in
writeShellApplication {
  name = "reuse-denoise";
  runtimeInputs = [
    ffmpeg-headless
    python
  ];
  text = ''
    if [ "$#" -ne 2 ]; then
      echo "usage: reuse-denoise INPUT OUTPUT_DIR" >&2
      exit 2
    fi

    input=$1
    output_dir=$2
    name=$(basename -- "$input")
    output=$output_dir/''${name%.*}.flac

    if [ -e "$output" ]; then
      echo "$output already exists" >&2
      exit 1
    fi

    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT
    mkdir "$work/input" "$work/output"

    ffmpeg -nostdin -loglevel error -i "$input" -vn -ac 1 -c:a pcm_f32le "$work/input/audio.wav"

    CUDA_VISIBLE_DEVICES=0 HF_HUB_CACHE=${hubCache} HF_HUB_OFFLINE=1 \
      python ${upstream}/inference_chunk.py \
      --input_folder "$work/input" \
      --output_folder "$work/output" \
      --config ${upstream}/recipes/${recipe} \
      --chunk_size_in_seconds 5 \
      --hop_length_portion 0.5 >&2

    mkdir -p "$output_dir"
    mv "$work/output/audio.flac" "$output"
    echo "$output"
  '';
}
