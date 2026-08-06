# Agent guidance

This repository is a local-only, fail-closed macOS Accessibility helper for ChatGPT. Preserve frontmost-app scoping, unrelated-key pass-through, final-title verification, and the boundary against network access or chat-content collection.

Shortcut configuration is dynamic, but model and effort values remain closed to the exact typed labels in source. Require at least Command, Option, or Control for every shortcut, reject duplicates, and keep unrelated-key pass-through. Invalid persisted configuration must disable switching until an explicit reset; do not add arbitrary labels or silent repair.

Before changing picker discovery, click delivery, phase ordering, permissions, or signing, read [ADR-001](ADR-001-accessibility-automation.md). Do not replace validated composer-relative targeting with fixed screen coordinates.

Run `swift test` for code changes. Changes to Accessibility behavior, signing, or profile mappings also require a signed Release build and a live check in an idle, normal-layout ChatGPT conversation; update the README and tests when the public behavior changes.
