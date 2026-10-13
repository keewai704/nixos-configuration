final: prev: {
  dsh = prev.dsh.overrideScope (
    dshFinal: dshPrev:
    let
      kernel =
        final.runCommand "dsh-kernel-cache-${dshPrev.dsh-kernel.version}"
          {
            inherit (dshPrev.dsh-kernel) version meta passthru;
            nativeBuildInputs = [
              final.patch
              final.nodejs-slim
            ];
          }
          ''
            mkdir -p "$out"
            cp -a ${dshPrev.dsh-kernel}/. "$out/"
            chmod -R u+w "$out"
            test -L "$out/lib/deepseek-harness/node_modules/.bin/js-yaml"
            "$out/lib/deepseek-harness/node_modules/.bin/js-yaml" --version
            patch --directory="$out" --fuzz=0 --strip=1 < ${./cache-compaction/compaction.patch}
            patch --directory="$out" --fuzz=0 --strip=1 < ${./cache-usage/kernel.patch}
            usage="$out/lib/deepseek-harness/node_modules/@deepseek-ai/dsh-token-meter/lib/cache-usage"
            mkdir -p "$usage"
            cp ${./cache-usage/accounting.mjs} "$usage/accounting.mjs"
            cp ${./cache-usage/schema.mjs} "$usage/schema.mjs"
            cp ${./cache-usage/projection.mjs} "$usage/projection.mjs"
            DSH_KERNEL_ROOT="$out/lib/deepseek-harness/node_modules/@deepseek-ai" \
              node --test ${./cache-compaction/compaction.test.mjs} ${./cache-usage/installed.test.mjs}
            node --test ${./cache-usage}/usage.test.mjs
          '';
      bundleWithKernel =
        bundle: extra:
        final.runCommand "${bundle.pname}-cache-${bundle.version}"
          {
            inherit (bundle)
              pname
              version
              meta
              passthru
              ;
            nativeBuildInputs = [
              final.python3
              final.patch
              final.nodejs-slim
            ];
          }
          ''
            mkdir -p "$out"
            cp -a ${bundle}/. "$out/"
            chmod -R u+w "$out"
            python3 - "$out" ${dshPrev.dsh-kernel} ${kernel} <<'PY'
            import os
            from pathlib import Path
            import sys

            root = Path(sys.argv[1]).resolve()
            old = sys.argv[2] + "/"
            new = sys.argv[3] + "/"
            for directory, dirs, files in os.walk(root, followlinks=False):
                for name in dirs + files:
                    link = Path(directory) / name
                    if link.is_symlink() and os.readlink(link).startswith(old):
                        assert link.parent.resolve().is_relative_to(root)
                        target = new + os.readlink(link)[len(old):]
                        assert Path(target).exists(), target
                        link.unlink()
                        link.symlink_to(target)
            for directory, dirs, files in os.walk(root, followlinks=False):
                for name in dirs + files:
                    link = Path(directory) / name
                    assert not (link.is_symlink() and os.readlink(link).startswith(old)), link
            PY
            ${extra}
            ${final.lib.getExe dshPrev.buildDshBundle.dshBundleResolver} manifest \
              "$out/nix-support/dsh-bundles.json" "$out/lib/node_modules"
          '';
    in
    {
      dsh-kernel = kernel;
      bundles = dshPrev.bundles.overrideScope (
        _: _:
        final.lib.mapAttrs
          (
            name: bundle:
            bundleWithKernel bundle (
              final.lib.optionalString (name == "web-app") ''
                patch --directory="$out" --fuzz=0 --strip=1 < ${./cache-usage/web.patch}
                node --check "$out/lib/node_modules/@deepseek-ai/dsh-web-app/node_modules/@deepseek-ai/dsh-client-ui-chat/lib/client.js"
                node --check "$out/lib/node_modules/@deepseek-ai/dsh-web-app/node_modules/@deepseek-ai/dsh-api-remotes/lib/client.js"
                DSH_KERNEL_ROOT="${kernel}/lib/deepseek-harness/node_modules/@deepseek-ai" \
                  DSH_WEB_ROOT="$out/lib/node_modules/@deepseek-ai/dsh-web-app/node_modules/@deepseek-ai" \
                  node --test ${./cache-usage/installed.test.mjs}
              ''
            )
          )
          (
            builtins.removeAttrs dshPrev.bundles (
              (builtins.attrNames dshPrev.removedBundles)
              ++ [
                "callPackage"
                "newScope"
                "overrideScope"
                "packages"
              ]
            )
          )
      );
      dsh = dshPrev.dsh.override {
        dsh-kernel = kernel;
        bundles = dshFinal.bundles;
      };
    }
  );
}
