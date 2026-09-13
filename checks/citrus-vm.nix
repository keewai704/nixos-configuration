{
  lib,
  pkgs,
  config,
}:
assert lib.assertMsg
  (
    config.networking.hostName == "citrus-vm"
    && config.virtualisation.hypervGuest.enable
    && config.fileSystems."/".device == "/dev/disk/by-label/nixos"
    && config.fileSystems."/boot".device == "/dev/disk/by-label/ESP"
    && !(config.fileSystems ? "/data")
    && config.swapDevices == [ ]
    && config.boot.loader.systemd-boot.enable
    && !config.boot.loader.limine.enable
    && !config.boot.loader.grub.enable
    && !(config.environment.sessionVariables ? AQ_DRM_DEVICES)
    && !(config.environment.sessionVariables ? LIBVA_DRIVER_NAME)
    && builtins.elem "hv_storvsc" config.boot.initrd.kernelModules
    && !(builtins.elem "nvidia" config.boot.initrd.kernelModules)
    && config.services.xserver.videoDrivers == [ "modesetting" ]
    && lib.any (
      dependency:
      builtins.elem "aquamarine-gbm.patch" (map builtins.baseNameOf (dependency.patches or [ ]))
    ) config.programs.hyprland.package.buildInputs
    && builtins.elem "hyprland-ime-modifiers.patch" (
      map builtins.baseNameOf config.programs.hyprland.package.patches
    )
    && !config.services.fprintd.enable
    && !config.hardware.bluetooth.enable
    && config.home-manager.users.keewai.programs.dynamic-island.enable
    && config.services.openssh.openFirewall
    && !config.services.openssh.settings.PasswordAuthentication
    && config.users.users.keewai.openssh.authorizedKeys.keys != [ ]
  )
  "citrus-vm must retain its desktop shell and use VM storage, drivers, bootloader, and key-only SSH";
pkgs.runCommand "citrus-vm-configuration-check" { } ''
  touch "$out"
''
