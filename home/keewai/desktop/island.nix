{ config, inputs, ... }:
{
  imports = [ inputs.island.homeManagerModules.default ];

  programs.island = {
    enable = true;
    wallpaper = config.stylix.image;
    bar = {
      style = "grouped";
      height = 32;
      hidden = false;
      left = [
        "workspaces"
        "overview"
        "split"
        "launcher"
      ];
      right = [
        "notifications"
        "network"
        "bluetooth"
        "volume"
        {
          id = "battery";
          figure = "on";
        }
        "split"
        {
          id = "pet";
          shape = "ring";
          figure = "off";
        }
        "split"
        {
          id = "claude";
          shape = "ring";
          figure = "off";
        }
        {
          id = "codex";
          shape = "ring";
          figure = "off";
        }
      ];
      chips = {
        shape = "icon";
        figure = "off";
      };
      workspaces = {
        style = "dots";
        count = 5;
      };
    };
    clock = {
      format = "HH:mm";
      date = false;
      seconds = false;
    };
    desktop.hidden = true;
    settings = {
      barMargin = 6;
      barSides = "capsule";
      barFullWidth = false;
      barShadow = false;
      islandAttached = false;
      surfaceStyle = "classic";
      desktopWidgets = [ ];
    };
  };
}
