{
  fetchFromGitHub,
  lkl,
  makeWrapper,
}:
lkl.overrideAttrs (previous: {
  version = "2026-02-16";
  src = fetchFromGitHub {
    owner = "lkl";
    repo = "linux";
    rev = "9dcd61afcc95c97aa925f62a4195fd4c1e440204";
    hash = "sha256-x0wzritqe2d+WBxu6t5nY+zI5NMaOrt99Ey0uCx8uT8=";
  };
  nativeBuildInputs = previous.nativeBuildInputs ++ [ makeWrapper ];
  postFixup = (previous.postFixup or "") + ''
    wrapProgram "$out/bin/cptofs" --add-flags "-m 1024"
  '';
})
