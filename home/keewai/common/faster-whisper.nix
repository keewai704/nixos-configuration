{ osConfig, pkgs, ... }:
{
  home.packages = [
    (
      if builtins.elem "nvidia" osConfig.services.xserver.videoDrivers then
        pkgs.local.whisper-ctranslate2-cuda
      else
        pkgs.whisper-ctranslate2
    )
  ];
}
