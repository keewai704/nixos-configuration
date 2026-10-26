{
  config,
  lib,
  pkgs,
  ...
}:
let
  package = pkgs.local.deepseek-harness;
  pluginRoot = "${package}/lib/deepseek-harness/node_modules";
  claudeExecutable = lib.getExe config.programs.claude-code.finalPackage;
  openWeb = pkgs.writeShellApplication {
    name = "dsh-open";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnused
      pkgs.systemd
      pkgs.xdg-utils
    ];
    text = ''
      systemctl --user start dsh-web.service
      invocation=$(systemctl --user show --property=InvocationID --value dsh-web.service)
      for _attempt in {1..50}; do
        url=$(journalctl --user --unit=dsh-web.service --invocation="$invocation" \
          --output=cat --no-pager | sed -n 's/^dsh web: //p' | tail -n 1)
        if [[ -n "$url" ]]; then
          exec xdg-open "$url"
        fi
        sleep 0.2
      done
      echo "DeepSeek Harness did not publish its URL; inspect journalctl --user -u dsh-web." >&2
      exit 1
    '';
  };
  settings = [
    {
      id = "claude-bridge";
      config.pathToClaudeCodeExecutable = claudeExecutable;
    }
    {
      id = "agent-default-model";
      config = {
        provider = "claude-bridge";
        model = "opus";
      };
    }
  ];
in
{
  home.packages = [
    package
    openWeb
  ];

  xdg.desktopEntries.deepseek-harness = {
    name = "DeepSeek Harness";
    exec = lib.getExe openWeb;
    icon = "${pluginRoot}/dsh-mobile-maxxing/packages/dsh-mobile-maxxing/assets/icon-192.png";
    categories = [ "Development" ];
    terminal = false;
  };

  home.activation.deepseekHarness = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    run ${lib.getExe' pkgs.coreutils "env"} DSH_HOME=${config.home.homeDirectory}/.dsh \
      ${lib.getExe package} plugin --profile web add \
      --offline --ignore-scripts --config.auto-install-peers=false \
      link:${pluginRoot}/dsh-claude-bridge \
      link:${pluginRoot}/dsh-mobile-maxxing \
      link:${pluginRoot}/rdsh-markdown-cjk \
      link:${pluginRoot}/rdsh-locale-ja \
      link:${pluginRoot}/dsh-codex-native
    ${lib.hm.generators.mkImpureConfigMerger {
      inherit pkgs;
      format = "yaml";
      empty = "[]";
      jqOperation = ''
        reduce $static[] as $entry ($dynamic;
          if any(.[]; .id == $entry.id) then
            map(if .id == $entry.id and .id == "claude-bridge" then
              .config.pathToClaudeCodeExecutable = $entry.config.pathToClaudeCodeExecutable
            else . end)
          else . + [$entry] end)
      '';
      path = "${config.home.homeDirectory}/.dsh/profiles/web/cordis.patch.yml";
      staticSettings = pkgs.writeText "deepseek-harness-settings.json" (builtins.toJSON settings);
      mode = "600";
    }}
  '';

  systemd.user.services.dsh-web = {
    Unit = {
      Description = "DeepSeek Harness Web UI with Claude and ChatGPT";
      After = [ "network.target" ];
    };
    Service = {
      ExecStart = "${lib.getExe package} web --host 127.0.0.1 --port 3080 --no-open";
      WorkingDirectory = config.home.homeDirectory;
      Environment = [
        "DSH_HOME=${config.home.homeDirectory}/.dsh"
        "DSH_TELEMETRY_MODE=DISABLED"
        "SHELL=${lib.getExe pkgs.zsh}"
        "PATH=/run/wrappers/bin:/etc/profiles/per-user/${config.home.username}/bin:/run/current-system/sw/bin"
      ];
      UMask = "0077";
      Restart = "on-failure";
      RestartSec = 5;
      TimeoutStopSec = 30;
    };
    Install.WantedBy = [ "default.target" ];
  };
}
