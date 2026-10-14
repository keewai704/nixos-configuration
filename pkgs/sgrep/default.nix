{
  lib,
  rustPlatform,
  fetchFromGitHub,
  fetchurl,
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

  env = {
    TSLP_LANGUAGES = "python,c,cpp,go,java,rust,typescript,tsx,javascript";
    TSLP_LINK_MODE = "static";
  };
  preBuild = ''
    cp ${
      fetchurl {
        url = "https://github.com/xberg-io/tree-sitter-language-pack/releases/download/v1.21.0/parser-sources-1.21.0.tar.zst";
        hash = "sha256-3TSlAd1pjEFEfUGUjww8ETIIns/+DrYN1ZdIU7TP0L8=";
      }
    } "$TMPDIR/parsers.tar.zst"
    printf '%s\n' dd34a501dd698c41447d41948f0c3c1132089ecffe0eb60dd5974853b4cfd0bf > "$TMPDIR/parsers.tar.zst.sha256"
    export TSLP_SOURCE_BUNDLE_URL="file://$TMPDIR/parsers.tar.zst"
  '';

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
