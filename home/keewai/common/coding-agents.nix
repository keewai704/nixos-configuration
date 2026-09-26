{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  claudeCode = inputs.claude-code.packages.${system}.default;
in
{
  programs.claude-code = {
    enable = true;
    package = pkgs.symlinkJoin {
      pname = "claude-code";
      inherit (claudeCode) version meta;
      paths = [ claudeCode ];
      nativeBuildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        wrapProgram $out/bin/claude \
          --set-default CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION false \
          --set-default CLAUDE_CODE_SIMPLE_SYSTEM_PROMPT 1 \
          --set-default ENABLE_CLAUDEAI_MCP_SERVERS false
      '';
    };
    enableMcpIntegration = false;
    context = ''
      # Delegating to Codex

      Use the `codex` subagent to offload non-UI work to OpenAI Codex (ChatGPT Pro, high limits):
      implementation, refactors, tests, debugging, research, and second-opinion reviews. Launch
      independent tasks in parallel. Name the Codex model and effort in the prompt when the default
      routing does not fit.

      Implement UI yourself: visual layout, styling, components, interaction, animation, theming,
      and user-facing copy. Codex may do the backend or data parts of a UI feature when you write
      the UI.

      Codex output is unverified. Review its diff and run the relevant checks before reporting or
      committing.
    '';
    agents.codex = ''
      ---
      name: codex
      description: Delegate a self-contained non-UI task (implementation, refactor, tests, debugging, research, review) to OpenAI Codex CLI and return its result. Not for UI, styling, or frontend visual work.
      tools: Bash, Read
      model: haiku
      ---

      You are a thin relay to Codex CLI. Do not solve the task yourself and do not rewrite it.

      1. Pick the model and effort. Use what the caller names; otherwise route:

         | Task | Model | Effort |
         | --- | --- | --- |
         | Architecture, hard debugging, concurrency, security, large or risky refactors, final reviews | `gpt-6-astra` | `xhigh` (`ultra` if the caller says it is very hard) |
         | Normal implementation, bug fixes, tests, medium refactors | `gpt-6-sol` | `high` |
         | Mechanical edits, bulk renames, codebase search, summaries, quick questions | `gpt-6-luna` | `medium` |

      2. Write the caller's full prompt verbatim to a file under `$XDG_RUNTIME_DIR/codex-subagent/`,
         appending: "Do not implement UI, styling, or frontend visual changes; report them as TODO
         for the caller. Finish with a concise summary of changed files, commands run, and results."

      3. Start Codex in the background with the caller's working directory:

         ```sh
         dir="$XDG_RUNTIME_DIR/codex-subagent"; mkdir -p "$dir"; id=$(date +%s%N)
         codex exec -m MODEL -c model_reasoning_effort=EFFORT -C WORKDIR \
           -o "$dir/$id.out" - < PROMPT_FILE > "$dir/$id.log" 2>&1 &
         echo "$id $!"
         ```

         Add `-s read-only` when the task only reads (research, questions, review). For reviewing
         changes, run `cd WORKDIR && codex exec review --uncommitted` (or `--base BRANCH`,
         `--commit SHA`) with the same `-m`, `-c`, and `-o` flags; it does not accept `-C` or `-s`.
         Add `--worktree` when the caller asks for isolation or other writers share the tree.

      4. Wait with `timeout 590 tail --pid=PID -f /dev/null` (Bash timeout 600000), repeating until
         the process exits. Do not use `sleep`.

      5. Return the contents of the `.out` file, the model and effort used, and the exit status. On
         failure, return the last 50 lines of the `.log` file. Never summarize away details.
    '';
  };

  home.activation.claudeCodeSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    settings="$HOME/.claude/settings.json"
    run mkdir -p "$HOME/.claude"
    [ -s "$settings" ] || run sh -c 'echo "{}" > "$1"' sh "$settings"
    tmp=$(mktemp)
    ${lib.getExe pkgs.jq} '.skipDangerousModePermissionPrompt = true | .remoteControlAtStartup = true' "$settings" > "$tmp"
    run sh -c 'cat "$1" > "$2"' sh "$tmp" "$settings"
    rm -f "$tmp"
  '';

  programs.codex = {
    enable = true;
    package = inputs.codex-cli.packages.${system}.default;
  };
}
