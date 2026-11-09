{ cudaPkgs, inputs, ... }:
{
  home-manager.users.keewai = {
    codingAgents.skills.faster-whisper = ../../skills/faster-whisper;

    home.packages = [
      (cudaPkgs.callPackage ../../pkgs/reuse-denoise {
        upstream = inputs.nemotronlabs-re-use;
        mambaSrc = inputs.mamba-ssm;
      })
      cudaPkgs.whisper-ctranslate2
    ];
  };
}
