{ pkgs, ... }:
{
  home.packages = [ (pkgs.callPackage ../../../pkgs/chatgpt-desktop { }) ];
  xdg.mimeApps.defaultApplications."x-scheme-handler/codex" = [ "chatgpt.desktop" ];
}
