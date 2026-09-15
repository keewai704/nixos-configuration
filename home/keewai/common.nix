{ pkgs, ... }:
{
  imports = [ ./shared ];

  programs.gh = {
    enable = true;
    settings = {
      accessible_colors = "disabled";
      accessible_prompter = "disabled";
      aliases.co = "pr checkout";
      browser = "";
      color_labels = "disabled";
      editor = "";
      git_protocol = "https";
      http_unix_socket = "";
      pager = "";
      prefer_editor_prompt = "disabled";
      prompt = "enabled";
      spinner = "enabled";
    };
  };

  xdg.configFile."gh/config.yml".force = true;

  home.packages = [
    pkgs.git
    pkgs.gws
    pkgs.ripgrep
    pkgs.yt-dlp
  ];
}
