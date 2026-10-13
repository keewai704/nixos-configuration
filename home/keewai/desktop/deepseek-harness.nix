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
    overlays = [ inputs.deepseek-harness.overlays.default ];
  };
  kernel = dshPkgs.callPackage ../../../pkgs/deepseek-harness/kernel.nix {
    kernel = dshPkgs.dsh.dsh-kernel;
  };
  compatibleBundle = dshPkgs.dsh.callPackage ../../../pkgs/deepseek-harness/compatible-bundle.nix { };
  claude = compatibleBundle (
    dshPkgs.dsh.callPackage ../../../pkgs/deepseek-harness/claude.nix {
      src = inputs.dsh-claude;
    }
  );
  claudeCode = inputs.claude-code.packages.${system}.default;
  tailnetHost = "citrus.tail1e65cd.ts.net";
  publicUrl = "https://${tailnetHost}:8443/";
in
{
  imports = [ inputs.deepseek-harness.homeModules.default ];

  home.packages = [
    (lib.hiPrio (
      pkgs.callPackage ../../../pkgs/deepseek-harness/launcher.nix {
        inherit publicUrl;
        inherit (config.services.dsh) package profile environment;
      }
    ))
  ];

  programs.dsh = {
    enable = true;
    package = dshPkgs.dsh.dsh.override { dsh-kernel = kernel; };
    defaultProfile = config.programs.dsh.profiles.web.materializedName;
    profiles.web = {
      bundles = [
        dshPkgs.dsh.bundles.web-app
        (compatibleBundle dshPkgs.dsh.bundles.subscriptions)
        claude
      ];
      patch = [
        {
          id = "connection";
          config.browserAuthentication = false;
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
    trustedHosts = [ "${tailnetHost}:8443" ];
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
      ExecStart = "${pkgs.tailscale}/bin/tailscale serve --bg --yes --https=8443 http://127.0.0.1:3080";
      ExecStop = "${pkgs.tailscale}/bin/tailscale serve --https=8443 off";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = [ "default.target" ];
  };
}
