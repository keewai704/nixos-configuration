{
  libfprint,
  fprintd,
  fetchFromGitHub,
  opencv4,
  doctest,
}:
let
  cs9711Libfprint = libfprint.overrideAttrs (old: {
    version = "1.94.10-cs9711";
    src = fetchFromGitHub {
      owner = "archeYR";
      repo = "libfprint-CS9711";
      rev = "02b285c9703c38d308fbe47a3c566ef1e7f883ca";
      hash = "sha256-QGrBNqbRNqLZIURI66xkenlQamNW+DQU4WS+CLN4zM8=";
    };
    buildInputs = old.buildInputs ++ [ opencv4 ];
    nativeBuildInputs = old.nativeBuildInputs ++ [ doctest ];
    patches = (old.patches or [ ]) ++ [ ./cs9711-cancellation.patch ];
    postInstallCheck = (old.postInstallCheck or "") + ''
      ./libfprint/sigfm/sigfm-tests
    '';
  });
in
(fprintd.override { libfprint = cs9711Libfprint; }).overrideAttrs (old: {
  doCheck = true;
  patches = (old.patches or [ ]) ++ [ ./fprintd-test-error-message.patch ];
})
