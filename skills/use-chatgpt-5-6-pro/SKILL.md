---
name: use-chatgpt-5-6-pro
description: Consult GPT-5.6 Sol Pro once in a Temporary Chat through the Codex in-app browser. Use for an explicit Pro consultation or when a blocked task needs an independent view; not for routine review, model selection, or API calls.
---

# Use ChatGPT 5.6 Pro

Use the signed-in ChatGPT web experience as an external reasoning surface. Use
a fresh Temporary Chat and at most one accepted Pro submission per invocation.

## Browser boundary

Use the available Codex in-app browser tool and follow its initialization and
returned API documentation before interacting. Load a browser skill if that
tool requires one; do not depend on a particular skill name being installed.
If in-app browser control is unavailable, report that limitation. Use only the
in-app browser and the requested model. Reuse an existing binding and ChatGPT
tab when available, but start a fresh Temporary Chat; otherwise open
`https://chatgpt.com/`.

If ChatGPT requires authentication, ask the user to sign in in the in-app
browser and tell you when it is ready. Do not inspect cookies, storage,
passwords, profiles, or other session data.

## One-message run

1. Prepare the single prompt and requested attachments before opening ChatGPT.
   For a blocked task, include the concrete question, relevant findings, and
   minimum context needed for an independent view. Ask first only if a missing
   input materially changes the answer or authorization; spend no submission
   until that input is available.
2. Inspect the current interactive page instead of relying on fixed selectors.
   Start a new Temporary Chat with the current UI and confirm that it is marked
   temporary before composing. Stop without sending if this cannot be confirmed.
3. Open the model picker in or near the composer and select `Pro`. Confirm that
   `Pro` is selected. Use the current UI to confirm that it maps to GPT-5.6 Sol
   Pro, consulting official OpenAI documentation only if the UI is insufficient;
   stop if the mapping cannot be confirmed.
4. If Pro is absent, disabled, unavailable to the signed-in account or
   workspace, or cannot be confirmed, stop and report the visible condition.
   Do not silently use Instant, Thinking, Extra High, another GPT-5.6 variant,
   or another model.
5. Submit the prepared prompt faithfully as one message. Include attachments
   only when requested. Do not send setup, model-check, prompt-refinement, or
   separate context messages, and never add secrets or unrelated private data.
6. Submit once and wait until generation finishes. If ChatGPT asks a material
   clarifying question, return it to the user instead of replying in ChatGPT.
   Retry only when the UI proves the original submission was not accepted;
   never retry while acceptance or generation status is uncertain.
7. Return the completed ChatGPT response clearly labeled as a GPT-5.6 Sol Pro
   result. Preserve useful links and citations. Distinguish its claims from
   independently verified facts, and perform separate verification only when
   the user's task requires it.

After the first response, end the Pro consultation and continue any remaining
authorized work in the original task. Do not continue the Pro conversation,
provide feedback, share it, or send another Pro message unless the user explicitly asks
after being told that another submission may consume additional usage or credits.
