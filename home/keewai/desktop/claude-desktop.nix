{
  config,
  inputs,
  pkgs,
  ...
}:
let
  package = pkgs.callPackage ../../../pkgs/claude-desktop {
    releases = inputs.claude-desktop-release;
    claude-code = config.programs.claude-code.finalPackage;
    codex = config.programs.codex.package;
    git = config.programs.git.package;
  };
in
{
  home.packages = [ package ];

  xdg.mimeApps.defaultApplications."x-scheme-handler/claude" = [ "com.anthropic.Claude.desktop" ];
}
