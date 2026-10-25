{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  community = inputs.noctalia-templates;
  communityTemplate =
    app: name:
    let
      directory = "${community}/${app}";
      template = (lib.importTOML "${directory}/template.toml").templates.${name};
    in
    template
    // {
      input_path = "${directory}/${template.input_path}";
    }
    // lib.optionalAttrs (template ? post_hook) {
      post_hook = lib.replaceStrings [ "{{ config_dir }}" ] [ directory ] template.post_hook;
    };
in
{
  programs.noctalia.settings.theme.templates = {
    enable_builtin_templates = true;
    enable_community_templates = true;
    builtin_ids = [
      "btop"
      "gtk3"
      "gtk4"
      "kcolorscheme"
      "qt"
      "umbriel"
    ];
    user = {
      kitty = {
        input_path = "${inputs.noctalia}/assets/templates/kitty/kitty.conf";
        output_path = "$XDG_CONFIG_HOME/kitty/themes/noctalia.conf";
        post_hook = "${lib.getExe' pkgs.procps "pkill"} -USR1 -x kitty || true";
      };
      bat = communityTemplate "bat" "bat" // {
        post_hook = "${lib.getExe config.programs.bat.package} cache --build";
      };
      fcitx5 = communityTemplate "fcitx5" "fcitx5";
      codex = communityTemplate "codex" "codex";
      claude-code = communityTemplate "claude-code" "claude-code";
      helium = communityTemplate "ungoogled-chromium" "ungoogled_chromium_theme" // {
        post_hook = "";
      };
      fzf = {
        input_path = pkgs.writeText "noctalia-fzf" (
          lib.concatLines (
            map (lib.removeSuffix "\"") (
              lib.filter (lib.hasPrefix "--color=") (
                lib.splitString "\n" (builtins.readFile "${community}/fzf/fzf.sh")
              )
            )
          )
        );
        output_path = "$XDG_CONFIG_HOME/fzf/noctalia";
      };
      legcord = {
        input_path = pkgs.writeText "noctalia-legcord.css" (
          builtins.readFile "${community}/discord/discord-system24.css"
          + import ./legcord-system24.nix { fonts = config.stylix.fonts; }
        );
        output_path = "$XDG_CONFIG_HOME/legcord/quickCss.css";
      };
      steam = {
        input_path = pkgs.writeText "noctalia-steam.css" (
          import ./steam.nix { fonts = config.stylix.fonts; }
        );
        output_path = "$XDG_CONFIG_HOME/millennium/quick.css";
      };
      starship = {
        input_path = pkgs.writeText "noctalia-starship.toml" (
          ''
            palette = "noctalia"
          ''
          + builtins.readFile ../../../common/shell/starship.toml
          + "\n"
          + builtins.readFile "${community}/starship/starship.toml"
        );
        output_path = "$XDG_CONFIG_HOME/starship.toml";
      };
    };
  };

  programs = {
    bat.config.theme = "noctalia";
    btop.settings.color_theme = "noctalia";
    claude-code.settings.theme = "custom:noctalia";
    codex.settings.tui.theme = "noctalia";
  };

  home.sessionVariables.FZF_DEFAULT_OPTS_FILE = "${config.xdg.configHome}/fzf/noctalia";

  xdg.configFile =
    lib.genAttrs [ "gtk-3.0/gtk.css" "gtk-4.0/gtk.css" ] (_: {
      text = ''@import url("noctalia.css");'';
    })
    // {
      "starship.toml".enable = false;
    };
}
