{
  config,
  lib,
  pkgs,
  osConfig,
  ...
}:
let
  tailnetHostname = "${osConfig.networking.hostName}.tail1e65cd.ts.net";
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
      id = "dsh-claude-agent";
      config.executable = claudeExecutable;
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
    profileManifest=${config.home.homeDirectory}/.dsh/profiles/web/package.json
    for previousPlugin in dsh-claude-bridge dsh-codex-native rdsh-locale-ja; do
      if [[ -f "$profileManifest" ]] && ${lib.getExe pkgs.jq} -e --arg plugin "$previousPlugin" \
        '.dependencies[$plugin] != null' "$profileManifest" > /dev/null; then
        run ${lib.getExe' pkgs.coreutils "env"} DSH_HOME=${config.home.homeDirectory}/.dsh \
          ${lib.getExe package} plugin --profile web remove "$previousPlugin" \
          --config.offline=true --config.ignore-scripts=true --config.auto-install-peers=false
      fi
    done
    run ${lib.getExe' pkgs.coreutils "env"} DSH_HOME=${config.home.homeDirectory}/.dsh \
      ${lib.getExe package} plugin --profile web add \
      --offline --ignore-scripts --config.auto-install-peers=false \
      link:${pluginRoot}/dsh-claude-agent \
      link:${pluginRoot}/dsh-mobile-maxxing \
      link:${pluginRoot}/rdsh-markdown-cjk \
      link:${pluginRoot}/dsh-locale-ja \
      link:${pluginRoot}/dsh-chatgpt-subscription \
      link:${pluginRoot}/dsh-subscription-usage
    ${lib.hm.generators.mkImpureConfigMerger {
      inherit pkgs;
      format = "yaml";
      empty = "[]";
      jqOperation = ''
        reduce $static[] as $entry ($dynamic | map(select(.id != "claude-bridge"));
          if any(.[]; .id == $entry.id) then
            map(if .id == $entry.id and .id == "dsh-claude-agent" then
              .config.executable = $entry.config.executable
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
      ExecStart = "${lib.getExe package} web --host 127.0.0.1 --port 3080 --no-open --public-url https://${tailnetHostname}/dsh/ --trusted-host ${tailnetHostname}";
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
