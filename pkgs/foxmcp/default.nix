{
  python3,
  writeShellApplication,
  upstream,
  mcpV1,
}:
let
  python = python3.override {
    self = python;
    packageOverrides = _: super: {
      mcp = super.mcp.overridePythonAttrs (old: {
        version = "1.${mcpV1.lastModifiedDate}";
        src = mcpV1;
        dependencies = with super; [
          anyio
          httpx
          httpx-sse
          jsonschema
          pydantic
          pydantic-settings
          pyjwt
          python-multipart
          sse-starlette
          starlette
          typing-extensions
          typing-inspection
          uvicorn
        ];
        doCheck = false;
      });
      fastmcp = super.fastmcp.overridePythonAttrs { doCheck = false; };
      fastmcp-slim = super.fastmcp-slim.overridePythonAttrs (old: {
        doCheck = false;
        doInstallCheck = false;
        meta = old.meta // {
          broken = false;
        };
      });
    };
  };

  env = python.withPackages (
    ps: with ps; [
      fastmcp
      httpx
      pydantic
      uvicorn
      websockets
    ]
  );
in
writeShellApplication {
  name = "foxmcp";
  text = ''
    exec ${env.interpreter} ${upstream}/server/server.py "$@"
  '';
}
