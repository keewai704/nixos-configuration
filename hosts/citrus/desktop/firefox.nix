{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  zen-browser = inputs.zen-browser;
  sineSources = (lib.importJSON "${zen-browser}/sources.json").addons.sine;
  mkSinePack =
    { }:
    {
      manager = pkgs.fetchFromGitHub {
        inherit (sineSources.manager)
          owner
          repo
          rev
          hash
          ;
      };
      bootloader = pkgs.fetchFromGitHub {
        inherit (sineSources.bootloader)
          owner
          repo
          rev
          hash
          ;
      };
    };
  sinePack = mkSinePack { };

  firefox = pkgs.firefox.overrideAttrs (old: {
    buildCommand = old.buildCommand + ''
      libDir=$out/lib/firefox
      chmod u+w $libDir/mozilla.cfg $libDir/defaults/pref/autoconfig.js
      echo 'pref("general.config.sandbox_enabled", false);' >> $libDir/defaults/pref/autoconfig.js
      cat ${zen-browser}/hm-module/sine-default-prefs.js ${sinePack.bootloader}/program/config.js >> $libDir/mozilla.cfg
    '';
  });

  profile = "default";
in
{
  home-manager.users.keewai =
    { config, ... }:
    let
      sine = lib.evalModules {
        specialArgs = { inherit pkgs; };
        modules = [
          (import "${zen-browser}/hm-module/sine.nix" { inherit mkSinePack; })
          {
            options = {
              home.file = lib.mkOption {
                type = lib.types.attrsOf lib.types.anything;
                default = { };
              };
              programs.zen-browser = {
                enable = lib.mkEnableOption "";
                profilesPath = lib.mkOption { type = lib.types.str; };
                activationFragments = lib.mkOption {
                  type = lib.types.attrsOf (lib.types.listOf lib.types.anything);
                  default = { };
                };
                profiles = lib.mkOption {
                  type = lib.types.attrsOf (
                    lib.types.submodule {
                      options = {
                        path = lib.mkOption { type = lib.types.str; };
                        settings = lib.mkOption {
                          type = lib.types.attrsOf lib.types.anything;
                          default = { };
                        };
                        presets.managedPrefNames = lib.mkOption {
                          type = lib.types.listOf lib.types.str;
                          default = [ ];
                        };
                      };
                    }
                  );
                };
              };
            };
            config.programs.zen-browser = {
              enable = true;
              profilesPath = "${config.home.homeDirectory}/${config.programs.firefox.profilesPath}";
              profiles.${profile} = {
                path = profile;
                sine = {
                  enable = true;
                  mods = [
                    "context-menu-icons"
                    "ff-better-findbar"
                  ];
                };
              };
            };
          }
        ];
      };
    in
    {
      programs.firefox = {
        enable = true;
        package = null;
        profiles.${profile} = {
          id = 0;
          isDefault = true;
          inherit (sine.config.programs.zen-browser.profiles.${profile}) settings;
        };
      };

      home.packages = [ firefox ];
      home.file = sine.config.home.file;
      home.activation.firefoxSineMods = inputs.home-manager.lib.hm.dag.entryAfter [ "writeBoundary" ] (
        lib.concatMapStrings (
          fragment: fragment.text
        ) sine.config.programs.zen-browser.activationFragments.${profile}
      );
    };
}
