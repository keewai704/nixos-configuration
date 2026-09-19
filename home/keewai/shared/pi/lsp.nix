{ lib, pkgs, ... }:
{
  home.file.".pi/agent/pi-lsp.json".text = builtins.toJSON {
    timeout = 20000;
    servers = {
      nixd = {
        command = [ (lib.getExe pkgs.nixd) ];
        extensions = [ ".nix" ];
      };
      typescript = {
        command = [
          (lib.getExe pkgs.typescript-language-server)
          "--stdio"
        ];
        extensions = [
          ".ts"
          ".tsx"
          ".mts"
          ".cts"
          ".js"
          ".jsx"
          ".mjs"
          ".cjs"
        ];
      };
      lua = {
        command = [ (lib.getExe pkgs.lua-language-server) ];
        extensions = [ ".lua" ];
        pushDiagnosticsGraceMs = 3000;
      };
      bash = {
        command = [
          (lib.getExe pkgs.bash-language-server)
          "start"
        ];
        extensions = [
          ".sh"
          ".bash"
        ];
        initialization.bashIde.shellcheckPath = lib.getExe pkgs.shellcheck;
      };
    };
  };
}
