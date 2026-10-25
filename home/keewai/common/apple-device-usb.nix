{ lib, pkgs, ... }:
let
  mobileDeviceCommand = import ./apple-device-command.nix { inherit lib pkgs; };
in
{
  programs.zsh.siteFunctions._pymobiledevice3 = ''
    #compdef pymobiledevice3
    eval "$(env _TYPER_COMPLETE_ARGS="''${words[1,$CURRENT]}" _PYMOBILEDEVICE3_COMPLETE=complete_zsh pymobiledevice3)"
  '';

  home.packages = [
    (mobileDeviceCommand {
      name = "pymobiledevice3";
      command = "pymobiledevice3";
    })
    (mobileDeviceCommand {
      name = "apple-device-usb";
      command = "python ${../../../skills/apple-device-usb/scripts}/control.py";
      runtimeInputs = [ pkgs.iproute2 ];
    })
  ];
}
