{
  libfprint,
  fprintd,
  fetchFromGitHub,
  opencv4,
  doctest,
}:
let
  cs9711Libfprint = libfprint.overrideAttrs (previousAttrs: {
    version = "1.94.10-cs9711";
    src = fetchFromGitHub {
      owner = "archeYR";
      repo = "libfprint-CS9711";
      rev = "02b285c9703c38d308fbe47a3c566ef1e7f883ca";
      hash = "sha256-QGrBNqbRNqLZIURI66xkenlQamNW+DQU4WS+CLN4zM8=";
    };
    buildInputs = previousAttrs.buildInputs ++ [ opencv4 ];
    nativeBuildInputs = previousAttrs.nativeBuildInputs ++ [ doctest ];
    patches = (previousAttrs.patches or [ ]) ++ [ ./cs9711-cancellation.patch ];
    postInstallCheck = (previousAttrs.postInstallCheck or "") + ''
      ./libfprint/sigfm/sigfm-tests
    '';
  });
in
(fprintd.override { libfprint = cs9711Libfprint; }).overrideAttrs (previousAttrs: {
  doCheck = true;
  patches = (previousAttrs.patches or [ ]) ++ [ ./fprintd-test-error-message.patch ];
})
