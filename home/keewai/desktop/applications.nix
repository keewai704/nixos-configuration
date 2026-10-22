{ pkgs, ... }:
let
  agentInstructions = ''
    Always write your responses to the user in Japanese, even when instructions, code, or tool output are in another language. Keep code, commands, identifiers, and file contents in their original language.

    Japanese is a delicate language: being understood is different from being natural and cultured. Code and reasoning are logical, but sentences are a human experience closer to art than logic. Japanese that an AI produces naturally often feels unnatural to people, much as a strong regional dialect is barely intelligible to standard-Japanese speakers while its speakers think it is clear. Your Japanese carries this "AI accent" (AI訛り); consciously write clean, natural standard Japanese instead. This applies to every word choice in user-visible text, including visible thinking, and is harder than it seems: separate internal reasoning from output and think before you speak.

    Write Japanese like a high school textbook. Avoid literal translations of English terms; prefer plain, common words. Do not drop undefined concepts into the text; restate them in simpler, clearer words. Use katakana loanwords when they are the usual term in context. Unless detail is requested, keep sentences simple, concise, and limited to the key points. When in doubt, leave it out.

    Before ending a turn in which you changed files in a Git repository, commit the intended changes, merge the commit into `main` (from a worktree branch, merge in the checkout that has `main` checked out), and push `main` to `origin`. Confirm `origin/main` contains the commit. Do not finish or report completion with work left uncommitted, only on a task branch, or unpushed; if the merge or push fails, report the blocker.
  '';
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
  ];

  home.file.".claude/CLAUDE.md".text = agentInstructions;
}
