packaging: final: prev:
let
  workspace = prev.dsh.dsh-workspace.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      ./small-fixes.patch
      ./reliability.patch
      ./workflow-policy.patch
      ./acp-approval.patch
    ];
  });
  kernel = prev.dsh.dsh-kernel.override { dsh-workspace = workspace; };
  cohort = prev.dsh.dshCohort.override { dsh-workspace = workspace; };
  generatedBundles = import (packaging + "/lib/dsh-optional-bundles.nix") {
    inherit (final) lib gitMinimal nodejs-slim;
    inherit (prev.dsh) buildDshBundle;
    dsh-workspace = workspace;
    dsh-kernel = kernel;
  };
  bundles = prev.dsh.bundles.overrideScope (
    _: bundlePrev:
    final.lib.mapAttrs (
      _: bundle:
      if final.lib.isDerivation bundle && bundle ? override then
        bundle.override (
          args:
          final.lib.intersectAttrs args {
            dsh-workspace = workspace;
            dsh-kernel = kernel;
            dshCohort = cohort;
          }
        )
      else
        bundle
    ) (final.lib.filterAttrs (name: _: !(builtins.hasAttr name prev.dsh.removedBundles)) bundlePrev)
    // generatedBundles
  );
in
{
  dsh = prev.dsh.overrideScope (
    _: dshPrev: {
      dsh-workspace = workspace;
      dsh-kernel = kernel;
      dshCohort = cohort;
      inherit bundles;
      dsh =
        (dshPrev.dsh.override {
          dsh-kernel = kernel;
          inherit bundles;
        }).overrideAttrs
          (old: {
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
