{ cudaPkgs, inputs, ... }:
let
  reuseDenoise = cudaPkgs.callPackage ../../pkgs/reuse-denoise {
    upstream = inputs.nemotronlabs-re-use;
    mambaSrc = inputs.mamba-ssm;
  };
in
{
  _module.args.reuseDenoise = reuseDenoise;

  home-manager.users.keewai = {
    codingAgents.skills.faster-whisper = ../../skills/faster-whisper;

    home.packages = [
      reuseDenoise
      cudaPkgs.whisper-ctranslate2
    ];
  };
}
