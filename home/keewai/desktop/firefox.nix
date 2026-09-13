{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  upstream = inputs.my-firefox-nix.nixosModules.default { inherit lib pkgs; };
  firefox = upstream.programs.firefox;
  profileDirectory = "${config.home.homeDirectory}/${config.programs.firefox.profilesPath}/${config.programs.firefox.profiles.default.path}";
in
{
  imports = [ upstream.home-manager.users.keewai ];

  programs.firefox = {
    inherit (firefox) enable languagePacks;
    package = firefox.package.override (previous: {
      extraPrefsFiles = (previous.extraPrefsFiles or [ ]) ++ [
        (pkgs.writeText "firefox-autoconfig.js" firefox.autoConfig)
      ];
    });
    policies = firefox.policies // {
      DisableAppUpdate = true;
      Preferences = lib.mapAttrs (_: value: {
        Value = value;
        Status = firefox.preferencesStatus;
      }) firefox.preferences;
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
