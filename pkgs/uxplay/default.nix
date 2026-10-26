{ uxplay }:
uxplay.overrideAttrs (previous: {
  patches = (previous.patches or [ ]) ++ [
    ./direct-video.patch
    ./dnssd-events.patch
  ];
})
