{ inputs, pkgs, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
  agentInstructions = ''
    Always write your responses to the user in Japanese, even when instructions, code, or tool output are in another language. Keep code, commands, identifiers, and file contents in their original language.

    When delegating to a subagent or child task, use only these Codex model and reasoning effort pairs, set explicitly through T3 Code's delegate_task (providerInstanceId codex, reasoningEffort option), and choose one per task instead of reusing one setting: gpt-6-luna with max for searches, lookups, and mechanical edits; gpt-6.1-sol with medium for routine implementation, tests, and summaries; gpt-6-astra with xhigh for hard design, debugging, or critical review. Do not use native subagent tools or other models for delegation. Honor any model or effort the user specifies.

    Before ending a turn in which you changed files in a Git repository, commit the intended changes, merge the commit into `main` (from a worktree branch, merge in the checkout that has `main` checked out), and push `main` to `origin`. Confirm `origin/main` contains the commit. Do not finish or report completion with work left uncommitted, only on a task branch, or unpushed; if the merge or push fails, report the blocker.
  '';
  t3codeRestart = pkgs.writeShellApplication {
    name = "t3code-restart";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gawk
      pkgs.jq
      pkgs.libnotify
      pkgs.procps
      pkgs.util-linux
    ];
    text = ''
      unit=t3code-restart
      delay=''${1:-0}
      if [[ ! $delay =~ ^[0-9]+$ ]]; then
        echo "usage: t3code-restart [delay-seconds]" >&2
        exit 2
      fi

      if [[ ''${T3CODE_RESTART_DETACHED:-} != 1 ]]; then
        systemd-run --user --unit="$unit" --collect --quiet \
          --description="Restart T3 Code" \
          -p KillMode=process \
          --setenv=T3CODE_RESTART_DETACHED=1 \
          "$(readlink -f "$0")" "$delay"
        echo "Started $unit.service; follow with: journalctl --user -u $unit -f"
        exit 0
      fi

      class=com.t3tools.T3Code
      pattern='/t3code-[^/ ]*-extracted/t3code'

      notify() {
        notify-send -a "T3 Code" "$@" || true
      }

      window_pids() {
        hyprctl -j clients | jq -r --arg class "$class" '.[] | select(.class == $class) | .pid'
      }

      t3code_units() {
        systemctl --user list-units --plain --no-legend --all --type=scope \
          "app-$class-*.scope" 'app-*t3code*.scope' | awk '$3 == "active" { print $1 }'
      }

      wait_until() {
        local seconds=$1
        shift
        for ((i = 0; i < seconds * 2; i++)); do
          if "$@"; then
            return 0
          fi
          sleep 0.5
        done
        return 1
      }

      no_t3code() {
        ! pgrep -f "$pattern" >/dev/null
      }

      has_window() {
        [[ -n $(window_pids) ]]
      }

      sleep "$delay"

      mapfile -t pids < <(window_pids)
      if ((''${#pids[@]} == 0)); then
        mapfile -t pids < <(pgrep -o -f "$pattern" || true)
      fi
      if ((''${#pids[@]} > 0)); then
        echo "Sending SIGTERM to T3 Code: ''${pids[*]}"
        kill -TERM "''${pids[@]}" 2>/dev/null || true
        wait_until 30 no_t3code || echo "T3 Code did not exit within 30 seconds"
      fi

      mapfile -t units < <(t3code_units)
      if ((''${#units[@]} > 0)); then
        echo "Stopping units: ''${units[*]}"
        timeout 20 systemctl --user stop "''${units[@]}" ||
          systemctl --user kill --signal=SIGKILL "''${units[@]}" || true
      fi

      if ! wait_until 5 no_t3code; then
        echo "Killing remaining T3 Code processes"
        pkill -KILL -f "$pattern" || true
        wait_until 5 no_t3code || true
      fi

      echo "Launching T3 Code"
      setsid -f uwsm app -- t3code.desktop </dev/null >/dev/null 2>&1

      if wait_until 90 has_window; then
        echo "T3 Code restarted: $(window_pids | tr '\n' ' ')"
        notify "T3 Code restarted"
      else
        echo "T3 Code window did not appear within 90 seconds" >&2
        notify -u critical "T3 Code restart failed" "journalctl --user -u $unit"
        exit 1
      fi
    '';
  };
in
{
  home.packages = [
    pkgs.brightnessctl
    pkgs.ddcutil
    pkgs.grimblast
    pkgs.idescriptor
    pkgs.iloader
    pkgs.moonlight-qt
    pkgs.pavucontrol
    t3codeRestart
    (pkgs.callPackage ../../../pkgs/t3code {
      release = inputs.t3code-release;
      claude-code = inputs.claude-code.packages.${system}.default;
      codex = inputs.codex-cli.packages.${system}.default;
    })
  ];

  home.file.".claude/CLAUDE.md".text = agentInstructions;
  home.file.".codex/AGENTS.md".text = agentInstructions;
}
