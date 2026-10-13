_: final: prev: {
  dsh = prev.dsh.overrideScope (
    _: dshPrev: {
      dsh = dshPrev.dsh.overrideAttrs (old: {
        nativeInstallCheckInputs = (old.nativeInstallCheckInputs or [ ]) ++ [ final.python3 ];
        postInstallCheck = (old.postInstallCheck or "") + ''
          DSH_TEST_PACKAGE="$out" ${final.lib.getExe final.python3} ${./operations/launcher-package.test.py}
        '';
        postInstall = (old.postInstall or "") + ''
          test "$(realpath "$out/bin/dsh")" = "$out/bin/dsh"
          test ! -e "$out/bin/dsh-unlocked"
          mv "$out/bin/dsh" "$out/bin/dsh-unlocked"
          makeWrapper ${final.lib.getExe final.python3} "$out/bin/dsh" \
            --add-flags ${./operations/launch-lock.py} \
            --add-flags "$out/bin/dsh-unlocked"
        '';
      });
    }
  );
}
