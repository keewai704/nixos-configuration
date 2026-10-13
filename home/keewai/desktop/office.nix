{ config, lib, ... }:
let
  applications = {
    word = {
      name = "Microsoft Word";
      icon = "x-office-document";
      category = "WordProcessor";
      mimeTypes = [
        "application/msword"
        "application/msword-template"
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        "application/vnd.openxmlformats-officedocument.wordprocessingml.template"
        "application/vnd.ms-word.document.macroEnabled.12"
        "application/vnd.ms-word.template.macroEnabled.12"
      ];
    };
    excel = {
      name = "Microsoft Excel";
      icon = "x-office-spreadsheet";
      category = "Spreadsheet";
      mimeTypes = [
        "application/vnd.ms-excel"
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        "application/vnd.openxmlformats-officedocument.spreadsheetml.template"
        "application/vnd.ms-excel.sheet.macroEnabled.12"
        "application/vnd.ms-excel.sheet.binary.macroEnabled.12"
        "application/vnd.ms-excel.template.macroEnabled.12"
      ];
    };
    powerpoint = {
      name = "Microsoft PowerPoint";
      icon = "x-office-presentation";
      category = "Presentation";
      mimeTypes = [
        "application/vnd.ms-powerpoint"
        "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        "application/vnd.openxmlformats-officedocument.presentationml.template"
        "application/vnd.openxmlformats-officedocument.presentationml.slideshow"
        "application/vnd.openxmlformats-officedocument.presentationml.slide"
        "application/vnd.ms-powerpoint.presentation.macroEnabled.12"
        "application/vnd.ms-powerpoint.template.macroEnabled.12"
        "application/vnd.ms-powerpoint.slideshow.macroEnabled.12"
        "application/vnd.ms-powerpoint.slide.macroEnabled.12"
      ];
    };
  };
in
{
  systemd.user.sessionVariables.FCITX_NO_PREEDIT_APPS = "wps.*,wpp.*,et.*,(winword|excel|powerpnt)[.]exe";

  home.file.".local/bin/bottles-development" = {
    source = ./bottles-development.py;
    executable = true;
    force = true;
  };

  xdg.desktopEntries = lib.mapAttrs' (application: settings: {
    name = "microsoft-${application}";
    value = {
      inherit (settings) name icon;
      mimeType = settings.mimeTypes;
      exec = "${config.home.homeDirectory}/.local/bin/bottles-development --office ${application} %F";
      terminal = false;
      categories = [
        "Office"
        settings.category
      ];
      startupNotify = true;
      settings.StartupWMClass =
        {
          word = "winword.exe";
          excel = "excel.exe";
          powerpoint = "powerpnt.exe";
        }
        .${application};
    };
  }) applications;

  xdg.mimeApps.defaultApplications = lib.concatMapAttrs (
    application: settings: lib.genAttrs settings.mimeTypes (_: [ "microsoft-${application}.desktop" ])
  ) applications;
}
