{ inputs, callPackage }:
(callPackage "${inputs.island}/nix/package.nix" {
  impasto = inputs.island.inputs.impasto;
}).overrideAttrs
  (previous: {
    postInstall = (previous.postInstall or "") + ''
      substituteInPlace "$out/share/island/hyprland.lua" \
        --replace-fail '    bind(main_mod .. " + S", shell("notes"), "Shell · Open the notes")' "" \
        --replace-fail '    bind(main_mod .. " + B", shell("board"), "Shell · Open the task board")' ""
    '';
  })
