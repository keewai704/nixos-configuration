{ pkgs, ... }:
let
  ponytailManagedHooks = pkgs.callPackage ../pkgs/ponytail-hooks { };
  codexSystemRequirements = (pkgs.formats.toml { }).generate "codex-requirements.toml" {
    features.hooks = true;
    hooks = {
      managed_dir = "${ponytailManagedHooks}/bin";

      SessionStart = [
        {
          matcher = "startup|resume|clear|compact";
          hooks = [
            {
              type = "command";
              command = "${ponytailManagedHooks}/bin/ponytail-activate";
              timeout = 5;
              statusMessage = "Loading ponytail mode...";
            }
          ];
        }
      ];

      UserPromptSubmit = [
        {
          hooks = [
            {
              type = "command";
              command = "${ponytailManagedHooks}/bin/ponytail-mode-tracker";
              timeout = 5;
              statusMessage = "Tracking ponytail mode...";
            }
          ];
        }
      ];
    };
  };
in
{
  environment.etc = {
    "codex/requirements.toml".source = codexSystemRequirements;
    "codex/skills/ponytail".source = ../skills/ponytail;
  };
}
