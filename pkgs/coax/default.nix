{
  lib,
  buildGo126Module,
  upstream,
  goText,
}:
buildGo126Module {
  pname = "coax";
  version = "0-unstable-${upstream.shortRev}";
  src = upstream;
  patches = [ ./acquired-parameters.patch ];
  vendorHash = null;
  postConfigure = ''
    GOFLAGS= go mod edit -replace=golang.org/x/text=${goText}
    GOFLAGS= go mod vendor
  '';
  subPackages = [
    "cmd/coax"
    "cmd/coaxd"
  ];
  env.CGO_ENABLED = 0;
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    go test ./internal/coaxd/demod/dib8096
    runHook postCheck
  '';
  ldflags = [
    "-s"
    "-w"
    "-X main.commit=${upstream.rev}"
  ];
  meta = {
    description = "USB tuner daemon and client";
    homepage = "https://github.com/Till0196/coax";
    license = lib.licenses.gpl2Only;
    platforms = lib.platforms.linux;
  };
}
