---
name: writing-skills
description: Use when creating, editing, or validating reusable agent skills, including changes to their trigger conditions and workflow instructions.
license: MIT
---

# Writing Skills

Apply the [Pi/Astra working agreement](../using-superpowers/SKILL.md).
For Nix-managed personal skills, also use the installed `add-nix-skill` skill
and edit repository sources rather than generated files.

Identify the recurring task or observed failure the skill addresses. Give it
one focused purpose, an accurate name, and a concise description explaining
when it should and should not trigger. Use Pi's documented Agent Skills format:
valid YAML frontmatter, a lowercase hyphenated name, and a nonempty description.
Read the body when applying a skill; its description is not the workflow.

Write a direct procedure with concrete inputs, decisions, and completion
evidence. State conditional behavior where it applies instead of combining
absolute rules with hidden exceptions. Preserve user precedence and repository
authority. Avoid redundant instructions, arbitrary iteration counts, universal
approval waits, and harness-specific tools that are not actually available.
Keep reusable helpers or references only when a real task needs them, use
relative links, and retain upstream license and revision information.

Validate frontmatter, discovery, duplicate names, and linked files with the
target loader. Check realistic matching, non-matching, ambiguous, and blocked
requests against the instructions. For changed behavior, use a bounded isolated
model evaluation when available and authorized; otherwise perform a manual
scenario review and report that limit. A loader pass is not behavioral proof.
Use a baseline comparison when diagnosing an actual behavioral regression,
not as a mandatory repeated paid evaluation for every wording edit.

Repair observed gaps and rerun only affected checks. Preserve existing work;
never delete a skill because testing happened after writing. Follow the
repository's review, commit, and deployment gates for the complete change set,
and verify deployed content. Do not push or publish merely because a skill was
authored, and do not restart the application owning the active task.
