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
    ./iphone-control
    ./noctalia
    ./kitty.nix
    ./legcord.nix
    ./office.nix
    ./penpot-mcp.nix
    ./scskiller
    ./stylix.nix
  ];

  codingAgents.globalInstructions = true;
}
