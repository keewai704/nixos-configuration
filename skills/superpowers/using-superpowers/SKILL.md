---
name: using-superpowers
description: Use when starting software development work or choosing a Superpowers workflow for design, implementation, debugging, or review. Not needed for greetings or unrelated questions.
license: MIT
---

# Using Superpowers in Pi

Apply the relevant workflow to the requested outcome. Read this entry once when
needed, then load individual skills through Pi's native discovery or
`/skill:<name>`. Resolve linked paths relative to this file. No special Skill
tool, bootstrap extension, task-list package, or browser companion is required.

## Working agreement

Explicit user instructions take precedence over skill guidelines. Follow the
applicable AGENTS.md and harness instructions for authorization, delegation,
file placement, checks, commits, and activation. Keep Ponytail's selected mode;
Superpowers supplies development workflows, not another simplicity policy.

An implementation request authorizes proceeding within its scope. Make routine
decisions from existing code and finish the work. Ask only when missing input
materially changes the result or authority. A design-only or review-only request
remains read-only. If a skill causes a pause, link its exact SKILL.md, quote the
instruction, and distinguish a requirement from your interpretation. Continue
independent authorized work while blocked.

Use the tools actually exposed by the current harness. In configured Pi, use
pi-crew's bundled roles, core subagent's inline tasks, or agent teams as appropriate;
inspect their distinct tool schemas and do not interchange their run IDs.
Follow the active delegation policy, honor opt-outs, and report unavailable
tools instead of pretending to call them. Keep remote operations, publication,
private-data uploads, and destructive cleanup within explicit authorization.

Run checks appropriate to the change. Reuse passing evidence with unchanged
inputs; rerun or broaden for changes, failures, or unresolved concerns. Required
runtime gates still apply. Do not turn small documentation or configuration
edits into mandatory code-test cycles, repeated reviews, or model evaluations.
Report the result, evidence, and limitations concisely in the user's language.

## Choose the next skill

- Unresolved product or design choices: [brainstorming](../brainstorming/SKILL.md).
- Multi-step implementation: [writing-plans](../writing-plans/SKILL.md), then
  [executing-plans](../executing-plans/SKILL.md) or
  [subagent-driven-development](../subagent-driven-development/SKILL.md).
- Independent concurrent tasks: [dispatching-parallel-agents](../dispatching-parallel-agents/SKILL.md).
- Isolation needed: [using-git-worktrees](../using-git-worktrees/SKILL.md).
- Behavior changes: [test-driven-development](../test-driven-development/SKILL.md).
- Failures or regressions: [systematic-debugging](../systematic-debugging/SKILL.md).
- Implementation review: [requesting-code-review](../requesting-code-review/SKILL.md)
  and [receiving-code-review](../receiving-code-review/SKILL.md).
- Completion claims: [verification-before-completion](../verification-before-completion/SKILL.md),
  then [finishing-a-development-branch](../finishing-a-development-branch/SKILL.md)
  when integration or handoff is needed.
- Skill authoring: [writing-skills](../writing-skills/SKILL.md).
- Unexpected Superpowers behavior: [diagnosing-superpowers](../diagnosing-superpowers/SKILL.md).

## Provenance

This local adaptation covers all 15 skills from
[Superpowers 6.4.1](https://github.com/obra/superpowers/tree/5bf4e78011075bcfc0dc295f0724994cd123ee71/skills),
revision `5bf4e78011075bcfc0dc295f0724994cd123ee71`, under the [MIT license](../LICENSE).
It uses the [Astra prompting guidance](https://developers.openai.com/api/docs/guides/latest-model#prompting-best-practices)
for follow-through, skill precedence, delegation, concise reporting, and scoped
verification. These files are maintained locally, not an unmodified upstream
plugin. Upstream hooks, executable helpers, and transcript export are not bundled.
