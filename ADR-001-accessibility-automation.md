# ADR-001: Accessibility automation strategy

- Status: Accepted
- Scope: ChatGPT model-and-effort selection in the macOS helper

## Context

ReasonDeck needs to change the active conversation's model and reasoning effort without modifying ChatGPT, depending on an undocumented private API, or retaining chat data. In the tested Chromium-based ChatGPT/Codex Mac app, the composer profile chip is not consistently exposed to Accessibility. Its native Select model command (`Control-Shift-M`) opens a picker whose top-level Model and Effort rows and nested exact choices are actionable Accessibility menu items. The UI also closes and rebuilds the menu after a model selection.

The safe target is therefore not merely a location on screen. It is the exact captured normal-conversation window, one native picker proven by its closed Model and Effort rows, owned menu content, and a verifiable final title.

## Decision

Use a frontmost-app-scoped event tap for user-configured shortcuts and drive ChatGPT through its native picker command plus macOS Accessibility:

1. Pass every key event through unless it is an exact, non-repeating match for a configured shortcut while ChatGPT is frontmost. Consume the matching key-down and corresponding key-up only. The event-tap callback captures only the matched entry, target, and process; it must not perform Accessibility discovery that could block long enough for macOS to disable the tap. Require every saved shortcut to include Command, Option, or Control so ordinary typing cannot be captured.
2. Immediately after the callback returns, require that same process to remain frontmost, capture its exact focused-window identity, and send ChatGPT's native `Control-Shift-M` command only after validating both. Never use arrow positions, fixed screen coordinates, or a generic composer-control fallback.
3. Accept the resulting picker only when the fresh captured window exposes exactly one pressable `AXMenuItem` Model row with one closed model value and one pressable `AXMenuItem` Effort row with one closed effort value. A label may live on a static-text child of that row, but a generic container that happens to contain the popover is not a row. ChatGPT's Accessibility parent references are not stable enough to prove a shared menu object across reads; duplicate, header, sidebar, preview, task, hidden, background, and geometry-only controls remain invalid.
4. Resolve Model/Effort choices only inside the one fresh submenu opened from that exact row. A row, menu, or exact-label ambiguity is a typed failure.
5. Apply model before effort. Reopen and rescan the native picker after every mutation because ChatGPT can rebuild the menu.
6. Verify the observed native picker title after each phase. Leave that verified picker visible so the next required phase can reacquire it from a fresh snapshot of the captured window instead of reopening it; never retain an Accessibility element or action target across phases. The phase returns its verified title to transaction orchestration, which must skip model or effort work that already matches. If effort fails after model succeeds, report a partial result without rollback.
7. Cleanup sends Escape only after a fresh snapshot proves that same native picker is still visible in the captured window. Every input action is sent once and is context-revalidated before and after delivery.
8. Before opening the picker, retain the exact focused `AXTextArea` only when it belongs to the captured ChatGPT window. After the transaction, restore focus to that same Accessibility element and verify it became the application's focused element. Never read its value, rediscover it by geometry, or redirect focus if the element, process, or window changed.
9. Fail closed when the frontmost app, native picker, labels, owned menu, actionable item, final title, or retained focus target cannot be verified.
10. Keep the bundle identifier and signing identity stable so macOS can associate Accessibility and Input Monitoring grants with a durable designated identity. Local live-development builds use a consistent Apple Development identity. Public builds require the intended Developer ID Application identity, hardened runtime, secure timestamp, notarization, and stapling. The release path fails instead of falling back to Apple Development, ad-hoc, or unsigned output.

Frontmost scoping is mandatory in the switching interface. Callers cannot opt into targeting a background process. The shortcut collection is dynamic and starts empty. Keyboard combinations must be unique, while model and effort selections remain configurable only from closed exact-label sets. Invalid persisted configuration disables switching until an explicit reset; it is never silently repaired.

Development and public distribution intentionally use different certificate classes, but the public application keeps the tracked bundle identifier `com.thierryai.ReasonDeck`. Certificate material, team-specific configuration, and notarization credentials remain outside source control. Every published upgrade must be verified against the same public designated identity before it is offered to users.

ChatGPT exposes one atomic selection operation. Callers may choose the ChatGPT selection and render its typed result, but cannot retain a picker, interleave model and effort actions, or cache a picker action target across a rerender. Focus restoration may retain only the exact text area focused before the transaction and must discard it if its window membership or identity becomes stale.

## Alternatives considered

### Private ChatGPT APIs or application injection

Rejected. They would couple the helper to undocumented internals, expand the privacy and security surface, and risk breaking ChatGPT's application integrity.

### Fixed screen coordinates

Rejected. Window size, display scale, composer height, and transient panels move the control. A fixed coordinate can click unrelated UI without proving what it targets.

### Keyboard-arrow navigation

Rejected. Arrow counts encode a transient menu order and can select the wrong model when ChatGPT changes account availability, grouping, or layout. The native command is used only to open the picker; every subsequent action is an exact Accessibility menu item.

### One atomic model-and-effort interaction

Rejected. Selecting a model closes and rebuilds the menu, so the effort selection requires a second verified interaction. Pretending the operation is atomic would hide real partial failure.

### Browser or DOM automation

Rejected. The product surface in scope is the native Mac app, and introducing a browser session would add a second UI and authentication context without removing the underlying drift risk.

## Consequences

- A full switch can visibly open the native model picker twice.
- The implementation is coupled to the English labels and native-picker Accessibility structure of tested ChatGPT versions.
- The normal conversation composer is the supported layout. Open-in preview/sidebar behavior remains unverified.
- ChatGPT UI changes require renewed Accessibility-tree and live behavior verification; a label or structure mismatch disables the unsafe path instead of guessing.
- The helper stays local-only and does not need chat content, account credentials, or network access.
- Configuration can express a supported model-and-effort pair that the current ChatGPT UI does not offer; runtime selection then reports the existing typed or partial failure without guessing.

## Supersession condition

Revisit this decision if ChatGPT provides a supported model-selection API or consistently exposes the composer picker and all menu choices as actionable Accessibility elements. Preserve frontmost scoping, final-state verification, and fail-closed behavior in any replacement.
