{
  lib,
  symlinkJoin,
  gnupatch,
  nodejs-slim,
  kernel,
}:
symlinkJoin {
  name = "${kernel.pname}-${kernel.version}-browser-auth";
  inherit (kernel)
    pname
    version
    meta
    passthru
    ;
  paths = [ kernel ];
  nativeBuildInputs = [ gnupatch ];
  postBuild = ''
    connection=lib/deepseek-harness/node_modules/@deepseek-ai/dsh-client-connection
    for file in lib/index.js lib/types/index.d.ts lib/types/rpc-host.d.ts; do
      cp --remove-destination "${kernel}/$connection/$file" "$out/$connection/$file"
      chmod u+w "$out/$connection/$file"
    done
    patch -d "$out/$connection" -p1 < ${./browser-auth.patch}
    ${lib.getExe nodejs-slim} --check "$out/$connection/lib/index.js"
  '';
}
