{ inputs, callPackage }:
(callPackage "${inputs.island}/nix/package.nix" {
  impasto = inputs.island.inputs.impasto;
}).overrideAttrs
  (previous: {
    patches = (previous.patches or [ ]) ++ [ ./restore-declarative-themes.patch ];
  })
