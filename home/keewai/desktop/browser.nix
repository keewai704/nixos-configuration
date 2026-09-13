{
  config,
  lib,
  pkgs,
  ...
}:

let
  braveOrigin = pkgs.callPackage ../../../pkgs/brave-origin { };

in
{
  home.packages = [ braveOrigin ];

  xdg = {
    configFile."mimeapps.list".force = true;
    configFile."BraveSoftware/Brave-Origin/NativeMessagingHosts/com.openai.codexextension.json".source =
      config.lib.file.mkOutOfStoreSymlink "${config.xdg.configHome}/BraveSoftware/Brave-Browser/NativeMessagingHosts/com.openai.codexextension.json";

    desktopEntries = {
      everglide-web-driver = {
        name = "TwinStar Webドライバー";
        comment = "EverglideキーボードをTwinStar WebHIDで設定";
        exec = "${lib.getExe braveOrigin} --app=https://v2-dev.xsyd.top/";
        icon = "input-keyboard";
        categories = [ "Settings" ];
        terminal = false;
      };

      openmouse = {
        name = "OpenMouse コントロールパネル";
        comment = "G PRO X SUPERLIGHT 2cなどの対応マウスをWebHIDで設定";
        exec = "${lib.getExe braveOrigin} --app=https://control.openmouse.app/";
        icon = "input-mouse";
        categories = [ "Settings" ];
        terminal = false;
      };
    };

    mimeApps = {
      enable = true;
      defaultApplications = {
        "application/xhtml+xml" = [ "brave-origin.desktop" ];
        "text/html" = [ "brave-origin.desktop" ];
        "x-scheme-handler/about" = [ "brave-origin.desktop" ];
        "x-scheme-handler/http" = [ "brave-origin.desktop" ];
        "x-scheme-handler/https" = [ "brave-origin.desktop" ];
        "x-scheme-handler/unknown" = [ "brave-origin.desktop" ];
      };
    };
  };
}
