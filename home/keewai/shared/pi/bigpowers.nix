{ lib, ... }:
{
  programs.pi-coding-agent.settings.packages = lib.mkOrder 1400 [
    {
      source = "npm:bigpowers@2.88.9";
      extensions = [ ];
    }
  ];
}
