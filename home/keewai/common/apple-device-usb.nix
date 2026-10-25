{ inputs, pkgs, ... }:
let
  packages = inputs.iphone-control.packages.${pkgs.stdenv.hostPlatform.system};
in
{
  programs.zsh.siteFunctions._pymobiledevice3 = ''
    #compdef pymobiledevice3
    eval "$(env _TYPER_COMPLETE_ARGS="''${words[1,$CURRENT]}" _PYMOBILEDEVICE3_COMPLETE=complete_zsh pymobiledevice3)"
  '';

  home.packages = [
    packages.pymobiledevice3
    packages.apple-device-usb
  ];
}
