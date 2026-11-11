let
  settings = import ../settings.nix;
in
{
  imports = [
    ./gpu-workloads.nix
    ./immich-machine-learning.nix
    ./plamo-server.nix
    ./stt-server
    (import ../../../modules/tailnet-web/t3code.nix settings)
    ./wake-on-lan.nix
    (import ../../../modules/tailnet-web settings)
  ];
}
