---
name: use-chatgpt-5-6-pro
description: Send one prompt to ChatGPT's GPT-5.6 Sol Pro in a Temporary Chat through the Codex in-app browser. Use when the user asks to consult ChatGPT 5.6 Pro or explicitly invokes this skill; do not use for ordinary Codex model selection or API calls.
---

# Use ChatGPT 5.6 Pro

Use the signed-in ChatGPT web experience as an external reasoning surface. Use
a fresh Temporary Chat and at most one accepted Pro submission per invocation.

## Browser boundary

Before any browser action, load and follow the complete
`browser:control-in-app-browser` skill. Use only the Codex in-app browser and
do not substitute Chrome, another browser, the OpenAI API, or a different
model. Reuse an existing in-app-browser binding and ChatGPT tab when available,
but never reuse its conversation; otherwise open `https://chatgpt.com/`.

If ChatGPT requires authentication, ask the user to sign in in the in-app
browser and tell you when it is ready. Do not inspect cookies, storage,
passwords, profiles, or other session data.

## One-message run

1. Before opening ChatGPT, ensure the prompt and every requested attachment are
   available. If a missing input would predictably require clarification, ask
   the user first and spend no Pro submission.
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
5. Submit the user's prompt faithfully as one message. Include files or context
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

After the first response, stop. Do not continue the conversation, provide
feedback, share it, or send another Pro message unless the user explicitly asks
after being told that another submission may consume additional usage or credits.
