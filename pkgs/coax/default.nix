{
  lib,
  buildGo126Module,
  upstream,
}:
buildGo126Module {
  pname = "coax";
  version = "0-unstable-${upstream.shortRev}";
  src = upstream;
  vendorHash = "sha256-zs0zADoen3Q447YPiX7s2X67iBReI9oB5xZ9gkM1Ui4=";
  subPackages = [
    "cmd/coax"
    "cmd/coaxd"
  ];
  env.CGO_ENABLED = 0;
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
