{ pkgs, ... }:
let
  shadcnUi = pkgs.fetchFromGitHub {
    owner = "shadcn-ui";
    repo = "ui";
    rev = "30a58d4498f270af1c1e981a7d78a15cf5740841";
    hash = "sha256-gQGhnAcdN+twTQQkFqbSxLUIRym0S19cWMzyg/gvg/U=";
  };
in
{
  codingAgents.skills.shadcn = "${shadcnUi}/skills/shadcn";

  home.packages = [ pkgs.nodejs ];
}
