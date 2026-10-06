---
name: penpot-apple-design
description: Design and inspect interfaces in Penpot, select current Apple UI assets for iOS, iPadOS, and macOS or suitable alternatives for Apple-inspired apps, and hand designs to implementation. Not for unrelated Apple device or build troubleshooting.
---

# Penpot and Apple app design

Use Penpot as the design workspace. Establish the target platform, minimum OS,
existing design file, and requested deliverable from the task before choosing
assets. An Apple-inspired web or Linux app needs different asset permissions
and implementation choices from a native Apple app.

## Select the relevant guidance

- For UI kits, symbols, fonts, app icons, device frames, or current Apple styling,
  read [Apple assets](references/apple-assets.md). Verify current official
  releases when selecting assets; its dated inventory is a starting point.
- For connection, canvas editing, libraries, tokens, prototypes, or exports,
  read [Penpot workflow](references/penpot.md). Prefer the Penpot MCP for design
  operations and inspect the live API before writing scripts.
- For implementation, retain Penpot's measured values and map documented
  platform behavior to native controls. CSS/HTML inspection is a web handoff,
  not generated SwiftUI, UIKit, or AppKit source.

## Desktop operations belong to Codex

Use browser automation for browser tasks when the harness provides it. In T3
Code, check `preview_status` and open the collaborative preview if needed.
Hypruse is for the local Hyprland desktop when desktop interaction is necessary,
such as an existing authenticated browser session or a native file dialog.

If already running as Codex, perform the necessary hypruse work directly.
Otherwise delegate that bounded desktop task to Codex. In T3 Code, discover the
live catalog with `orchestrator_capabilities` and use `delegate_task` with
`providerInstanceId: codex` and an explicit `reasoningEffort` option: choose
`gpt-6-luna` / `max` for inspection or mechanical operations,
`gpt-6.1-sol` / `medium` for routine implementation and verification, or
`gpt-6-astra` / `xhigh` for difficult debugging. Honor an explicit user override.
Retain the returned task ID; do not create an ordinary top-level conversation.
If the required Codex route is unavailable, report the desktop blocker and
continue independent asset or design work.

Give the operator the exact file/window, intended actions, permitted changes,
and evidence to return. Only one operator may control that window at a time.
Call hypruse `desktop` first; use IPC for window management and fresh screenshots
for actions inside windows. Login and access requirements remain in force.
Hypruse cannot operate a Mac or physical iPhone/iPad; use `apple-device-usb`
only when the task actually calls for an authorized physical device check.

## Delivery

Return the Penpot file/page or board identifiers, useful previews or exports,
asset source/version/check date, substitutions, and implementation notes relevant
to the requested work. Distinguish a visual approximation from a native behavior
verified on the target OS. If the editor is disconnected, finish the asset plan
and identify the missing connection without claiming a design was created.
