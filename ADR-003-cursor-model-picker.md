# ADR-003: Cursor Agent/Chat model picker adapter

- Status: Accepted; signed live smoke verified on Cursor 3.15.6 and 3.16.29 on macOS 26.5.1
- Scope: Cursor Agent and Chat model-and-effort selection in the Cursor Mac app

## Context

ReasonDeck already switches ChatGPT and Claude Code Desktop from one physical shortcut with independent assignments. Cursor exposes the active model in Agent/Chat chrome and opens a picker from that control. Cursor is Electron-based and model labels are partly server-driven, so synthetic input still requires strict frontmost scoping and observable verification.

## Decision

1. Store an optional, independently typed Cursor assignment alongside ChatGPT and Claude Code. At least one assignment must remain enabled.
2. Keep configuration version 2. Decode a missing Cursor field as unset; do not invent Cursor defaults during ChatGPT-only or Claude-only migration.
3. Consume a matching event only when Cursor (`com.todesktop.230313mzl4w4u92`) is frontmost and enabled for the entry. Capture the process at key-down without blocking the event-tap callback, then immediately require that process to remain frontmost and capture its focused-window identity before dispatch.
4. Require a visible model chip in the active Agent or Chat surface before any selection attempt. If Accessibility does not expose that control, fail closed with `cursorModelControlUnavailable` and change nothing.
5. Identify one active composer by the structural relationship among a text input, the exact `Add agents, context, tools` popup, and a model/effort popup. Do not read text-input values or search transcript text.
6. Open the parameters menu through the composer chip and require a second stable observation. Resolve its exact `Model` or closed-set `Model <current model>` label across one bounded structural row. Resolve effort from the exact typed value or `Effort <typed value>`. Open the owned `Model selection` menu, require at least two distinct closed-set models, and select one exact row. Never use list position, substring guessing, settings-file edits, or VS Code command injection.
7. Prefer direct `AXPress` or `AXShowMenu` only when the exact control has no usable frame. Cursor 3.16 can report those actions on the composer popup and verified menu rows while treating them as no-ops. A HID click is therefore permitted for the one structurally verified framed composer chip and for a unique framed exact-label row inside a verified menu. Every click requires exact process/window revalidation immediately before delivery, derives its point from current element/menu geometry, restores the pointer at transaction end, and is followed by strict observable-state verification after Cursor's transient composer rebuild.
8. Cursor may rebuild the composer or expose only effort on the chip after a model change. Keep each action target coupled to the exact AX snapshot that produced it, wait for two stable observations of the requested model (or a bounded stable unexposed state), then reopen the owned parameters menu to observe the exact model. Select effort if needed, reopen once more, and require both final values. Send at most one Escape, only while a verified owned menu remains open.
9. If the picker never opens, report `cursorPickerDidNotOpen`. If it opens but the requested typed model/effort row is absent, report `cursorMenuItemMissing`. Never substitute another model or effort. When the chip and parameters menu already prove the assignment, report already-applied.

## Consequences

- The same shortcut can select different profiles depending on which supported app is frontmost.
- Cursor UI, Accessibility exposure, or display-name drift disables the adapter instead of selecting by position.
- Signed live verification covered repeated GPT-5.6 Sol High ↔ Grok 4.6 High transitions, idempotence, and a mid-operation frontmost-app change on Cursor 3.15.6, plus a verified Auto-to-GPT-5.6-Sol-High transition on Cursor 3.16.29. On 3.16.29, selecting Auto is a partial result because Cursor exposes the model but no effort control. The broader release matrix remains a separate promotion gate.
- Effort applies only when Cursor exposes that exact label for the selected model; otherwise ReasonDeck reports partial or unavailable results.

## Supersession condition

Prefer an official local Cursor model API that preserves active-session scoping and verifiable final state. Revisit Max Mode, Fast-only parameters, and richer thinking menus when they expose stable, exact Accessibility labels distinct from the closed sets in source.
