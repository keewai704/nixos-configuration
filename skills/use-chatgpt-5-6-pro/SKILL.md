---
name: use-chatgpt-5-6-pro
description: Use ChatGPT's GPT-5.6 Sol Pro through the Codex in-app browser when the user asks to send a prompt to ChatGPT 5.6 Pro or explicitly invokes this skill. Do not use for ordinary Codex model selection, API calls, or requests that do not ask to consult ChatGPT Pro.
---

# Use ChatGPT 5.6 Pro

Use the signed-in ChatGPT web experience as an external reasoning surface while
keeping the user's requested prompt and browser choice intact.

## Browser boundary

Before any browser action, load and follow the complete
`browser:control-in-app-browser` skill. Use only the Codex in-app browser and
do not substitute Chrome, another browser, the OpenAI API, or a different
model. Reuse an existing in-app-browser binding and suitable ChatGPT tab when
available; otherwise open `https://chatgpt.com/` in the in-app browser.

If ChatGPT requires authentication, ask the user to sign in in the in-app
browser and tell you when it is ready. Do not inspect cookies, storage,
passwords, profiles, or other session data.

## Run the request

1. Use the conversation named by the user. If none is named, start a new chat
   so unrelated history does not influence the answer.
2. Inspect the current interactive page instead of relying on fixed selectors.
   Open the model picker in or near the composer and select `Pro`. Confirm that
   the conversation shows `Pro` as selected before sending anything. Also
   confirm from the current UI or official OpenAI documentation that `Pro`
   still maps to GPT-5.6 Sol Pro; stop if that mapping cannot be confirmed.
3. If Pro is absent, disabled, unavailable to the signed-in account or
   workspace, or cannot be confirmed, stop and report the visible condition.
   Do not silently use Instant, Thinking, Extra High, another GPT-5.6 variant,
   or another model.
4. Submit the user's prompt faithfully. Include files or additional context
   only when the user requested them. Never add hidden instructions, secrets,
   unrelated workspace content, or private conversation context.
5. Wait until ChatGPT finishes generating. If it asks a material clarifying
   question, return that question to the user rather than inventing an answer.
   For a transient page or generation error, make at most one safe retry; do
   not send duplicate prompts when the first submission may still be running.
6. Return the completed ChatGPT response clearly labeled as a GPT-5.6 Sol Pro
   result. Preserve useful links and citations. Distinguish its claims from
   independently verified facts, and perform separate verification only when
   the user's task requires it.

Do not continue the ChatGPT conversation, provide feedback, share it, archive
it, or delete it unless the user asks.
