{ cudaPkgs, pkgs, ... }:
{
  home-manager.users.keewai = {
    codingAgents.skills.faster-whisper = ../../skills/faster-whisper;

    home.packages = [
      pkgs.local.reuse-denoise
      cudaPkgs.whisper-ctranslate2
    ];
  };
}
