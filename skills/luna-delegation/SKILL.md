---
name: luna-delegation
description: Delegate substantial, separable coding, research, document, or data support batches to in-conversation gpt-5.6-luna sub-agents at max reasoning while the primary agent keeps intent, architecture, integration, and final review; do not trigger for simple answers or one tiny command.
---

# Luna delegation

Preserve the primary conversation's configured reasoning effort. Keep the primary Astra
agent responsible for understanding user intent, choosing the architecture,
handling difficult or ambiguous reasoning, integrating results, and performing
the final review.

Delegate a bounded support batch to `gpt-5.6-luna` with
`reasoning_effort=max` and `fork_turns=none` when all of these are true:

- The task is substantial and the batch is independently checkable.
- The work is high-volume, repetitive, retrieval-heavy, or likely to consume a
  material amount of reasoning or credit budget.
- The batch has a clear input, output, and stopping point, and the primary
  agent has useful work that can proceed in parallel.

Typical qualifying batches include:

- Repository search, caller inventory, dependency tracing, or focused code
  reconnaissance.
- Focused research against official documentation, with source comparison and
  exact citations or links.
- Triage of large logs, test failures, lint output, or build diagnostics.
- Agreed repetitive edits across a reserved set of files.
- Running the selected existing tests, linters, or local builds and returning
  exit status and relevant diagnostics; live activation stays with the primary.
- Long-document extraction, table construction, or a bounded first draft.

Do not invoke this skill for a simple conversational answer, one tiny command,
or work that cannot be separated cleanly. Do not delegate everything, assume
that more agents always help, or promise lower cost or guaranteed credit
savings. Use one agent for each coherent batch, reuse an existing agent for
that same batch, and avoid duplicate reading or duplicate implementation.

Brief the agent with the smallest context that makes the batch executable. The
brief must state the bounded objective, allowed inputs and sources, any reserved
file ownership, and the required report: findings, exact file/line or source
references, commands and check results, changed paths, and unresolved facts.
Ask it to stop after that report unless the explicitly bounded batch includes
the approved edits.

For a qualifying batch, call `collaboration.spawn_agent` directly with:

```json
{
  "model": "gpt-5.6-luna",
  "reasoning_effort": "max",
  "fork_turns": "none",
  "task_name": "inspect_callers",
  "message": "Inspect <bounded inputs> for <specific objective>. Do not duplicate the primary agent's work or take live, remote, destructive, or external-communication actions. Return findings, exact references, check results, changed paths, and unresolved facts; stop when this batch is complete."
}
```

Keep delegation inside the current conversation's sub-agent tree. Use
`collaboration.send_message`, `collaboration.followup_task`, and
`collaboration.wait_agent` to coordinate with the sub-agent and collect its result.
`fork_turns=none` starts the sub-agent without inherited history; it does not
create a standalone user task.

Do not substitute `create_thread`, `fork_thread`, or `send_message_to_thread`
for sub-agent delegation. A separate user task requires an explicit request
for a separate task; asking for a sub-agent does not authorize one. If
`collaboration.spawn_agent` is unavailable, report that limitation and continue
the work in the primary conversation without creating a separate task.

Delegation does not change existing authorization, host boundaries, trust
boundaries, or repository ownership. Do not have a sub-agent rebuild or alter a
live system while the primary agent is editing. Reserve file ownership before
delegated edits and never allow concurrent writes to the same file. The primary
agent reviews every delegated change and owns integration and final decisions.

Use RTK for supported shell commands. Keep bulky raw diagnostics in a local
file and return the relevant evidence and file path instead of the full log.

Do not treat `rtk gain`, output length, or an agent's estimate as a measurement
of credits consumed or saved. Report resource use only when the platform gives
an explicit usage result; otherwise describe the work and its verification.
