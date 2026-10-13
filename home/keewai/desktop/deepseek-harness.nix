{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  dshPkgs = import inputs.deepseek-harness.inputs.nixpkgs {
    inherit system;
    overlays = [
      inputs.deepseek-harness.overlays.default
      (import ../../../pkgs/deepseek-harness/overrides.nix inputs.deepseek-harness)
    ];
  };
  compatibleBundle = dshPkgs.dsh.callPackage ../../../pkgs/deepseek-harness/compatible-bundle.nix { };
  claude = compatibleBundle (
    dshPkgs.dsh.callPackage ../../../pkgs/deepseek-harness/claude.nix {
      src = inputs.dsh-claude;
    }
  );
  claudeCode = inputs.claude-code.packages.${system}.default;
  tailnetHost = "citrus.tail1e65cd.ts.net";
  publicUrl = "https://${tailnetHost}/";
in
{
  imports = [ inputs.deepseek-harness.homeModules.default ];

  home.packages = [
    (dshPkgs.dsh.callPackage ../../../pkgs/deepseek-harness/maintenance.nix { })
    (lib.hiPrio (
      pkgs.callPackage ../../../pkgs/deepseek-harness/launcher.nix {
        inherit publicUrl;
        inherit (config.services.dsh) package profile environment;
      }
    ))
  ];

  xdg.desktopEntries.deepseek-harness = {
    name = "DeepSeek Harness";
    genericName = "Coding Agent Web UI";
    exec = "dsh web";
    icon = "utilities-terminal";
    categories = [ "Development" ];
    terminal = false;
  };

  programs.dsh = {
    enable = true;
    package = dshPkgs.dsh.dsh;
    defaultProfile = config.programs.dsh.profiles.web.materializedName;
    profiles.web = {
      bundles = [
        dshPkgs.dsh.bundles.web-app
        (compatibleBundle dshPkgs.dsh.bundles.subscriptions)
        claude
        (dshPkgs.dsh.callPackage ../../../pkgs/deepseek-harness/operations.nix { })
      ];
      patch = [
        {
          id = "operations";
          config.persistence = "launch-reset";
        }
        {
          id = "agent-default-model";
          config = {
            provider = "codex";
            model = "gpt-6-astra";
            reasoningEffort = "max";
          };
        }
        {
          id = "system-prompt";
          config.personaSuffix = ''
            Whenever you delegate work, always use the `workflow` tool and its `agent(...)` hook, including for a single task or one or two delegations. Do not use `subagent` or `subagent_fork`. This deployment policy overrides earlier guidance that limits workflow to explicit workflow requests or large multi-agent orchestration, prefers plain subagent calls for small delegations, or tells you to start delegations with `subagent` or `subagent_fork`. It does not require delegation when you can complete the task directly.

            Give every `agent(...)` call a self-contained prompt with the task, necessary context, constraints, working directory, and expected result; do not assume it inherits the parent conversation. Use `parallel(...)` for independent tasks and `pipeline(...)` for per-item stages. When independent work remains in the parent, set `run_in_background: true`, track the returned job id, and continue that work; collect the result with `job_output` before finishing.
          '';
        }
        {
          id = "llm-subscriptions";
          config.providers = [ "codex" ];
        }
        {
          id = "llm-claude-code";
          config = {
            claudeCommand = lib.getExe claudeCode;
            executablePolicy = "host-only";
            passEnv = [
              "PATH"
              "CLAUDE_CODE_DISABLE_CLAUDE_MDS"
              "CLAUDE_CODE_DISABLE_ATTACHMENTS"
              "CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS"
            ];
          };
        }
      ];
    };
  };

  services.dsh = {
    enable = true;
    profile = config.programs.dsh.defaultProfile;
    workspace = "${config.home.homeDirectory}/nixos-configuration";
    listenAddress = "127.0.0.1";
    port = 3080;
    trustedHosts = [ tailnetHost ];
    extraArguments = [
      "--public-url"
      publicUrl
    ];
    environment = {
      PATH =
        lib.makeBinPath [
          claudeCode
          pkgs.nodejs
          pkgs.git
          pkgs.bashInteractive
          pkgs.coreutils
        ]
        + ":/etc/profiles/per-user/keewai/bin:/run/current-system/sw/bin";
      CLAUDE_CODE_DISABLE_CLAUDE_MDS = "1";
      CLAUDE_CODE_DISABLE_ATTACHMENTS = "1";
      CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS = "1";
    };
  };

  systemd.user.services.dsh-tailscale = {
    Unit = {
      Description = "Publish DeepSeek Harness over Tailscale HTTPS";
      After = [ "dsh-web.service" ];
      Wants = [ "dsh-web.service" ];
    };
    Service = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.tailscale}/bin/tailscale serve --bg --yes --https=443 http://127.0.0.1:3080";
      ExecStop = "${pkgs.tailscale}/bin/tailscale serve --https=443 off";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = [ "default.target" ];
  };
}
