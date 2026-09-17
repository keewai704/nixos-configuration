{ pkgs }:
pkgs.mkShellNoCC {
  packages = with pkgs; [
    nixd
    nixfmt
    statix
    deadnix
    lua-language-server
    stylua
    bash-language-server
    shellcheck
    shfmt
  ];
}
