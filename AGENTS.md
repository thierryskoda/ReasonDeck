# Agent guidance

This repository is a local-only, fail-closed macOS Accessibility helper for ChatGPT, Claude Code Desktop, and Cursor. Preserve frontmost-app scoping, unrelated-key pass-through, final-state verification, and the boundary against network access or chat-content collection.

Shortcut configuration is dynamic, but model and effort values remain closed to the exact typed labels in source. Require at least Command, Option, or Control for every shortcut, reject duplicates, and keep unrelated-key pass-through. Invalid persisted configuration must disable switching until an explicit reset; do not add arbitrary labels or silent repair. For Cursor, require a visible model chip before switching; fail closed when Accessibility does not expose that control or an exact picker label.

Before changing picker discovery, click delivery, phase ordering, permissions, or signing, read [ADR-001](ADR-001-accessibility-automation.md), [ADR-002](ADR-002-claude-code-desktop.md), [ADR-003](ADR-003-cursor-model-picker.md), [ADR-004](ADR-004-cursor-unread-navigation.md), and [ADR-005](ADR-005-antigravity-model-picker.md). Do not replace validated composer-relative or documented menu-shortcut targeting with fixed screen coordinates.

Run `swift test` for code changes. Changes to Accessibility behavior, signing, or profile mappings also require a signed Release build and a live check in an idle, normal-layout target session; update the README and tests when the public behavior changes.

Treat documentation as part of substantive implementation and fixes. Before finishing, reconcile changed behavior, accepted strategy, non-obvious constraints, and reusable failure lessons with one authoritative owner: source comments for local rationale, tests/types/tooling for enforceable contracts, the README for current public or setup behavior, and ADRs for durable cross-cutting decisions. Update affected pointers instead of duplicating explanations, and do not preserve a work log or abandoned approach unless its failure constrains future choices.

Add concise source comments where code could otherwise look arbitrary or be "simplified" into breaking a safety property. Explain the why, invariant, platform quirk, ordering constraint, or fail-closed reason—not what the syntax does. Keep each comment beside the code it protects, update or remove it when the behavior changes, and inspect nearby tests and ADRs before deleting an odd-looking workaround.
