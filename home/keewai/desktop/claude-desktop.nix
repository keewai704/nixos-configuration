{
  config,
  pkgs,
  ...
}:
let
  package = pkgs.local.claude-desktop.override {
    claude-code = config.programs.claude-code.finalPackage;
    git = config.programs.git.package;
  };
in
{
  home.packages = [ package ];

  xdg.mimeApps.defaultApplications."x-scheme-handler/claude" = [ "com.anthropic.Claude.desktop" ];
}
