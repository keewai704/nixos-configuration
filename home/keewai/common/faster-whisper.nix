{ pkgs, ... }:
{
  home.packages = [
    pkgs.local.reuse-denoise
    pkgs.whisper-ctranslate2
  ];
}
