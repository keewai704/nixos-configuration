{ aquamarine }:
aquamarine.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [ ./aquamarine-gbm.patch ];
})
