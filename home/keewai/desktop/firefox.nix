{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  upstreamModule = inputs.my-firefox-nix.nixosModules.default { inherit lib pkgs; };
  upstreamFirefox = upstreamModule.programs.firefox;
  lockedPreferences = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (
      name: value: "lockPref(${builtins.toJSON name}, ${builtins.toJSON value});"
    ) upstreamFirefox.preferences
  );
  profileDirectory = "${config.home.homeDirectory}/${config.programs.firefox.profilesPath}/${config.programs.firefox.profiles.default.path}";
in
{
  imports = [ upstreamModule.home-manager.users.keewai ];

  programs.firefox = {
    inherit (upstreamFirefox) enable languagePacks;
    package = upstreamFirefox.package.override (previous: {
      extraPrefsFiles = (previous.extraPrefsFiles or [ ]) ++ [
        (pkgs.writeText "firefox-autoconfig.js" ''
          ${lockedPreferences}
          ${upstreamFirefox.autoConfig}
        '')
      ];
    });
    policies = upstreamFirefox.policies // {
      DisableAppUpdate = true;
    };
    profiles.default.isDefault = true;
  };

  stylix.targets.firefox.enable = false;

  home.activation.initializeFirefoxProfile =
    lib.hm.dag.entryBetween [ "installSine" ] [ "linkGeneration" ]
      ''
        profile_dir=${lib.escapeShellArg profileDirectory}
        run ${pkgs.coreutils}/bin/mkdir -p "$profile_dir"
        if [[ ! -e "$profile_dir/prefs.js" ]]; then
          run ${pkgs.coreutils}/bin/touch "$profile_dir/prefs.js"
        fi
      '';
}
