{
  inputs,
  lib,
  pkgs,
  ...
}:
{
  programs.nix-ld.libraries = with pkgs; [
    cairo
    dbus
    ffmpeg_6
    fontconfig
    freetype
    giflib
    libglvnd
    libjpeg8
    libpng
    libpulseaudio
    libtiff
    libx11
    libxcursor
    libxext
    libxkbfile
    libxml2_13
    libxrandr
    vulkan-loader
  ];

  systemd.tmpfiles.rules = [ "d /opt 0755 root root -" ];

  home-manager.users.keewai = {
    codingAgents = {
      skills.agent-sim = inputs.agent-sim + "/skills/agent-sim";
      mcpServers.agent-sim = {
        command = lib.getExe pkgs.local.agent-sim;
        args = [ "mcp" ];
      };
    };

    home.packages = [ pkgs.local.agent-sim ];
  };
}
