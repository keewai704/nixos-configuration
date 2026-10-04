{
  lib,
  pkgs,
  ...
}:

let
  helium = pkgs.callPackage ../../../pkgs/helium { };

in
{
  home.packages = [ helium ];

  xdg = {
    configFile."mimeapps.list".force = true;
    configFile."net.imput.helium/WidevineCdm/latest-component-updated-widevine-cdm".text =
      builtins.toJSON
        { Path = "${pkgs.widevine-cdm}/share/google/chrome/WidevineCdm"; };

    desktopEntries = {
      everglide-web-driver = {
        name = "TwinStar Webドライバー";
        comment = "EverglideキーボードをTwinStar WebHIDで設定";
        exec = "${lib.getExe helium} --app=https://v2-dev.xsyd.top/";
        icon = "input-keyboard";
        categories = [ "Settings" ];
        terminal = false;
      };

      openmouse = {
        name = "OpenMouse コントロールパネル";
        comment = "G PRO X SUPERLIGHT 2cなどの対応マウスをWebHIDで設定";
        exec = "${lib.getExe helium} --app=https://control.openmouse.app/";
        icon = "input-mouse";
        categories = [ "Settings" ];
        terminal = false;
      };
    };

    mimeApps = {
      enable = true;
      defaultApplications = {
        "application/xhtml+xml" = [ "helium.desktop" ];
        "text/html" = [ "helium.desktop" ];
        "x-scheme-handler/about" = [ "helium.desktop" ];
        "x-scheme-handler/http" = [ "helium.desktop" ];
        "x-scheme-handler/https" = [ "helium.desktop" ];
        "x-scheme-handler/unknown" = [ "helium.desktop" ];
      };
    };
  };
}
