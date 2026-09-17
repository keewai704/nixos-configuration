{ pi-coding-agent }:
pi-coding-agent.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [ ./cache-affinity-header.patch ];
})
