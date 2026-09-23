---
name: add-nix-skill
description: Create or revise Nix-managed personal skills. Not for invoking skills or editing repository-only guidance.
---

# Add a Nix-managed skill

Edit `skills/` in the actual nixos-configuration checkout, not deployed links.
Use its [AGENTS.md](/home/keewai/nixos-configuration/AGENTS.md) for repository
gates and absolute checkout paths when working elsewhere. Reuse completed
preparation; do not restart a generic workflow for each skill.

## Author and publish

For a new or substantially revised skill, read Pi's bundled `docs/skills.md`
and use available skill-authoring guidance. Keep one focused purpose, a concise
description, and only the references or scripts the workflow needs. Repository
operational gates belong in AGENTS.md rather than being repeated in the skill.

Home Manager publishes `skills/<name>` directories, including Ponytail, under
`~/.agents/skills` through
[shared/skills.nix](/home/keewai/nixos-configuration/home/keewai/shared/skills.nix).
Pi discovers these directories natively. Check publication filters when adding,
renaming, or removing a skill.

Use the available editing tools on the source. Do not reinitialize an existing
skill or write into generated skill directories. Cross-project routing
preferences belong in
[shared/pi/APPEND_SYSTEM.md](/home/keewai/nixos-configuration/home/keewai/shared/pi/APPEND_SYSTEM.md).
Preserve unrelated metadata and package-managed resources.

## Verify skill behavior

Validate changed skills with the pinned Pi skill loader using temporary state,
without making a model request. Confirm each intended skill is discovered and
no validation diagnostics are returned. Check frontmatter, linked files, and
relative paths against Pi's documented Agent Skills format. If the loader is
unavailable, report that limit and validate the format with a temporary parser;
do not add a permanent repository test suite.

For material trigger or workflow changes, check realistic matching and
non-matching requests against the new instructions. Verify decisions and
boundaries, not exact wording; report whether this was a manual scenario review
or an executed model evaluation. Keep this check within the authorized
resources and the user's delegation policy.

In addition to AGENTS.md's checks, verify the Home Manager file set or built
links. After applicable local `test` and `switch`, confirm Home Manager success
and compare each deployed skill with its repository source. Keep tests of any
mode controls isolated from the active session.

Use AGENTS.md's evaluated-host impact rule for deployment. If the client has
not reloaded a changed skill, tell the user to open a new task or restart the
app after completion; do not terminate the application owning the task.
