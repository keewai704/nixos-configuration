---
name: superpowers
description: Coordinate complex design, implementation, debugging, or review when needed, or use on explicit request. Not routine edits.
license: MIT
---

# Superpowers

Choose the guidance needed for the current task, not a fixed itinerary. Read only
the matching reference below; loading this skill does not enable every workflow.
Routine edits with a known approach can proceed directly.

Define completion from the request and repository rules. For implementation,
continue through authorized checks, repairs, required review, and delivery. Ask
only when missing information materially changes the result or authority; keep
design-only and review-only requests read-only. This guidance does not add
approval or review gates beyond the request, repository, and active harness.

## Choose guidance

| Need | Read |
| --- | --- |
| Materially unresolved requirements or design choices | [Brainstorming](references/brainstorming.md) |
| A coordinated implementation plan | [Writing plans](references/writing-plans.md) |
| Carrying out an existing plan in this session | [Executing plans](references/executing-plans.md) |
| Independent tasks worth running concurrently | [Parallel agents](references/dispatching-parallel-agents.md) |
| Implementer contexts worth separating | [Subagent-driven development](references/subagent-driven-development.md) |
| Isolation from other changes or writers | [Git worktrees](references/using-git-worktrees.md) |
| An unexplained failure or regression | [Systematic debugging](references/systematic-debugging.md) |
| Executable behavior needing regression coverage | [Test-driven development](references/test-driven-development.md) |
| An independent assessment of changes | [Requesting review](references/requesting-code-review.md) |
| Review findings to evaluate and resolve | [Receiving review](references/receiving-code-review.md) |
| Evidence for a completion claim | [Verification](references/verification-before-completion.md) |
| Integration, deployment, or handoff | [Finishing work](references/finishing-a-development-branch.md) |
| Creating or revising a reusable skill | [Writing skills](references/writing-skills.md) |
| Unexpected Superpowers behavior in a session | [Diagnosing Superpowers](references/diagnosing-superpowers.md) |

Use the active harness's exposed tools and configured agents.
Follow the active delegation policy and preserve Ponytail's selected mode.
Honor a request to disable Superpowers without dropping repository-required gates.

## Source

Locally adapted from all 15 skills in
[Superpowers 6.4.1](https://github.com/obra/superpowers/tree/5bf4e78011075bcfc0dc295f0724994cd123ee71/skills),
revision `5bf4e78011075bcfc0dc295f0724994cd123ee71`, under the [MIT license](LICENSE).
The entry replaces `using-superpowers`; the other workflows are supporting
references, not separately advertised skills. This version follows
[OpenAI's Astra guidance](https://developers.openai.com/blog/rethinking-skills-and-prompts-for-gpt-6-astra)
and [Anthropic's Opus guidance](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5):
narrow triggers, progressive disclosure, clear completion and stop boundaries,
and durable progress without a fixed thinking ritual. Upstream bootstrap hooks,
executable helpers, and transcript export are not included.
