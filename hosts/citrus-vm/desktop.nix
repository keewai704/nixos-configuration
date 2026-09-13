{ inputs, lib, ... }:
{
  nixpkgs.overlays = lib.mkAfter [
    (_final: previous: {
      hyprland = previous.hyprland.override {
        aquamarine =
          inputs.hyprland.inputs.aquamarine.packages.${previous.stdenv.hostPlatform.system}.aquamarine.overrideAttrs
            (old: {
              patches = (old.patches or [ ]) ++ [ ./aquamarine-gbm.patch ];
            });
      };
    })
  ];

  services.xserver.videoDrivers = lib.mkForce [ "modesetting" ];
  environment.sessionVariables = {
    AQ_DRM_DEVICES = lib.mkForce null;
    LIBVA_DRIVER_NAME = lib.mkForce null;
    __GLX_VENDOR_LIBRARY_NAME = lib.mkForce null;
    LIBGL_ALWAYS_SOFTWARE = "1";
    QT_QUICK_BACKEND = "software";
  };
}
