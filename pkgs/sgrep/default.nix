{
  lib,
  rustPlatform,
  fetchFromGitHub,
  makeWrapper,
  ripgrep,
}:
rustPlatform.buildRustPackage {
  pname = "sgrep";
  version = "0.3.0-unstable-7452784";

  src = fetchFromGitHub {
    owner = "context-dot-dev";
    repo = "sgrep";
    rev = "745278422a650f02e97101c1395e52e159b7afb7";
    hash = "sha256-iRR/kk5wNNSD8/oh9lQ2jo9yaOlbNekdIuUXwKaDQf4=";
  };
  cargoHash = "sha256-t8hluTvIkvklAaHASs4CXS59JhqTYd9Xo1sAXJ4P3S0=";

  nativeBuildInputs = [ makeWrapper ];
  postInstall = ''
    wrapProgram "$out/bin/sgrep" --prefix PATH : ${lib.makeBinPath [ ripgrep ]}
  '';

  meta = {
    description = "Local semantic code and text search";
    homepage = "https://github.com/context-dot-dev/sgrep";
    license = lib.licenses.mit;
    mainProgram = "sgrep";
  };
}
