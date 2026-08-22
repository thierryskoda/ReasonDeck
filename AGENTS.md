# Agent guidance

This repository is a local-only, fail-closed macOS Accessibility helper for ChatGPT, Claude Code Desktop, and Cursor. Preserve frontmost-app scoping, unrelated-key pass-through, final-state verification, and the boundary against network access or chat-content collection.

Shortcut configuration is dynamic, but model and effort values remain closed to the exact typed labels in source. Require at least Command, Option, or Control for every shortcut, reject duplicates, and keep unrelated-key pass-through. Invalid persisted configuration must disable switching until an explicit reset; do not add arbitrary labels or silent repair. For Cursor, require a visible model chip before switching; fail closed when Accessibility does not expose that control or an exact picker label.

Before changing picker discovery, click delivery, phase ordering, permissions, or signing, read [ADR-001](ADR-001-accessibility-automation.md), [ADR-002](ADR-002-claude-code-desktop.md), [ADR-003](ADR-003-cursor-model-picker.md), and [ADR-004](ADR-004-cursor-unread-navigation.md). Do not replace validated composer-relative or documented menu-shortcut targeting with fixed screen coordinates.

Run `swift test` for code changes. Changes to Accessibility behavior, signing, or profile mappings also require a signed Release build and a live check in an idle, normal-layout target session; update the README and tests when the public behavior changes.
