{ legcord }:
legcord.overrideAttrs (previous: {
  patches = (previous.patches or [ ]) ++ [ ./rpc-lifecycle.patch ];
})
