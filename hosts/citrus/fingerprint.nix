{ pkgs, ... }:

let
  # Upstream libfprint does not support the attached 2541:0236 reader yet.
  libfprint = pkgs.libfprint.overrideAttrs (old: {
    version = "1.94.10-cs9711";
    src = pkgs.fetchFromGitHub {
      owner = "archeYR";
      repo = "libfprint-CS9711";
      rev = "02b285c9703c38d308fbe47a3c566ef1e7f883ca";
      hash = "sha256-QGrBNqbRNqLZIURI66xkenlQamNW+DQU4WS+CLN4zM8=";
    };
    buildInputs = old.buildInputs ++ [ pkgs.opencv4 ];
    nativeBuildInputs = old.nativeBuildInputs ++ [ pkgs.doctest ];
    patches = (old.patches or [ ]) ++ [ ./cs9711-cancellation.patch ];
    postInstallCheck = (old.postInstallCheck or "") + ''
      ./libfprint/sigfm/sigfm-tests
    '';
  });
in
{
  services.fprintd = {
    enable = true;
    package = (pkgs.fprintd.override { inherit libfprint; }).overrideAttrs (old: {
      doCheck = true;
      patches = (old.patches or [ ]) ++ [ ./fprintd-test-error-message.patch ];
    });
  };

  security.pam.services.sshd.fprintAuth = false;
}
