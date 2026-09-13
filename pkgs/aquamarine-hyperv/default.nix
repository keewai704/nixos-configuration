{ aquamarine }:
aquamarine.overrideAttrs (previousAttrs: {
  patches = (previousAttrs.patches or [ ]) ++ [ ./aquamarine-gbm.patch ];
})
