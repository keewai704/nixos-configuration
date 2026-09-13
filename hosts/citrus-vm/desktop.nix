{ lib, ... }:
{
  services.xserver.videoDrivers = lib.mkForce [ "modesetting" ];
  environment.sessionVariables = {
    AQ_DRM_DEVICES = lib.mkForce null;
    LIBVA_DRIVER_NAME = lib.mkForce null;
    __GLX_VENDOR_LIBRARY_NAME = lib.mkForce null;
    LIBGL_ALWAYS_SOFTWARE = "1";
    QT_QUICK_BACKEND = "software";
  };

  home-manager.users.keewai.imports = [ ../../home/keewai/citrus-vm ];
}
