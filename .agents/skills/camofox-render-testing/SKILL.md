---
name: camofox-render-testing
description: Render and test web pages with Camofox Browser. Use whenever a task needs browser-visible rendering, UI or layout verification, interaction testing, screenshot evidence, DOM or accessibility inspection, or reproduction of a browser-only issue, including verification after frontend changes. Do not trigger for HTTP/API-only checks or source review with no rendered page.
---

# Camofox Rendering Tests

Treat the page rendered by Camofox as the evidence for browser-facing results.

## Workflow

1. Identify the target URL, states to exercise, and expected behavior. For a local application, start or reuse its approved development server and record the URL.
2. Open the target with `camofox_create_tab` and retain the returned tab ID. Use `camofox_navigate` for later navigation in the same flow.
3. Inspect `camofox_snapshot` before interacting. Prefer snapshot refs for `camofox_click` and `camofox_type`; scroll when the target state is below the fold.
4. Capture `camofox_screenshot` for each state that supports a visual conclusion.
5. Use `camofox_evaluate` only for bounded browser assertions that the snapshot cannot establish clearly. Useful checks include:
   - `document.readyState`, `document.title`, and `location.href`
   - viewport and document dimensions
   - horizontal overflow
   - loaded images whose `naturalWidth` is zero
   - task-relevant computed styles, focus state, or visible text
6. Exercise the interactions relevant to the request, such as navigation, form input, menus, dialogs, scrolling, and post-action states. Capture the resulting state before declaring it correct.
7. Record the actual viewport. When a request requires distinct viewport sizes and the available Camofox session cannot change size, report that constraint instead of inferring results for untested sizes.
8. Close tabs opened for the test unless the user asks to keep them available.

## Failure handling

- Preserve a screenshot and the relevant snapshot or DOM assertion for a failure before changing code.
- After a fix, repeat the same flow and capture fresh evidence.
- Classify authentication prompts, bot challenges, unavailable local endpoints, and network errors as environment blockers unless the application itself caused them.
- Never report a visual state as tested when it was inferred from source code alone.

## Report

State the tested URL and interaction state, pass or fail result, observed viewport, relevant assertions, and screenshot evidence. Keep environment limitations separate from application failures.
