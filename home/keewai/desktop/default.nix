{
  imports = [
    ./packages.nix
    ./apple-music
    ./apple-sharing
    ./bitwarden.nix
    ./browser.nix
    ./file-manager.nix
    ./umbriel.nix
    ./input-method.nix
    ./noctalia
    ./kitty.nix
    ./legcord.nix
    ./office.nix
    ./penpot-mcp.nix
    ./scskiller
    ./stylix.nix
  ];

  codingAgents.globalInstructions = true;
  services.t3code.mode = "desktop";
}
