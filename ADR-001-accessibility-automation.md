# ADR-001: Accessibility automation strategy

- Status: Accepted
- Scope: ChatGPT model-and-effort selection in the macOS helper

## Context

ModelKey needs to change the active conversation's model and reasoning effort without modifying ChatGPT, depending on an undocumented private API, or retaining chat data. In the tested Chromium-based ChatGPT/Codex Mac app, the composer profile picker and its nested menus are not consistently exposed as directly actionable Accessibility pop-up controls. The UI also closes and rebuilds the menu after a model selection.

The safe target is therefore not merely a location on screen. It is the profile control in the active ChatGPT window's normal composer, with recognizable labels, bounded geometry, actionable menu content, and a verifiable final title.

## Decision

Use a frontmost-app-scoped event tap for user-configured shortcuts and drive ChatGPT through macOS Accessibility with a validated geometry fallback:

1. Pass every key event through unless it is an exact, non-repeating match for a configured shortcut while ChatGPT is frontmost. Consume the matching key-down and corresponding key-up only. Require every saved shortcut to include Command, Option, or Control so ordinary typing cannot be captured.
2. Resolve the active ChatGPT window and search for a picker that already exposes an Accessibility press action.
3. If no actionable picker exists, accept only a bounded group near the bottom composer that contains a known model or effort title, then derive the click point relative to that validated group. Never persist absolute screen coordinates.
4. Prefer `AXPress` for actionable rows and items. When Chromium exposes a framed control without a usable press action, deliver a HID-level click at the derived point and immediately restore the previous cursor position.
5. Apply model before effort. Re-resolve the picker after model selection because ChatGPT closes and rebuilds the menu and may reset or constrain available effort values.
6. Verify the observed picker title after each phase. Skip phases that already match. If effort fails after model succeeds, report a partial result without rollback.
7. Fail closed when the frontmost app, composer picker, labels, actionable item, or final title cannot be verified.
8. Keep the bundle identifier and signing identity stable so macOS can associate Accessibility and Input Monitoring grants with a durable designated identity. Local live-development builds use a consistent Apple Development identity. Public builds require the intended Developer ID Application identity, hardened runtime, secure timestamp, notarization, and stapling. The release path fails instead of falling back to Apple Development, ad-hoc, or unsigned output.

Frontmost scoping is mandatory in the switching interface. Callers cannot opt into targeting a background process. The shortcut collection is dynamic and starts empty. Keyboard combinations must be unique, while model and effort selections remain configurable only from closed exact-label sets. Invalid persisted configuration disables switching until an explicit reset; it is never silently repaired.

Development and public distribution intentionally use different certificate classes, but the public application keeps the tracked bundle identifier `com.thierryai.ModelKey`. Certificate material, team-specific configuration, and notarization credentials remain outside source control. Every published upgrade must be verified against the same public designated identity before it is offered to users.

Freshly verified window and picker context may be cached for at most one second between phases. Selection operations return their observed title to the coordinator so verification does not repeat a full Accessibility traversal. These are bounded performance optimizations, not a relaxation of the verification rules.

## Alternatives considered

### Private ChatGPT APIs or application injection

Rejected. They would couple the helper to undocumented internals, expand the privacy and security surface, and risk breaking ChatGPT's application integrity.

### Fixed screen coordinates

Rejected. Window size, display scale, composer height, and transient panels move the control. A fixed coordinate can click unrelated UI without proving what it targets.

### Process-targeted synthetic mouse events

Rejected for the fallback path. Live testing found that the Chromium renderer ignored process-targeted mouse delivery for this control. System HID-level delivery worked, but it must be used only after validating the target and must restore the pointer.

### One atomic model-and-effort interaction

Rejected. Selecting a model closes and rebuilds the menu, so the effort selection requires a second verified interaction. Pretending the operation is atomic would hide real partial failure.

### Browser or DOM automation

Rejected. The product surface in scope is the native Mac app, and introducing a browser session would add a second UI and authentication context without removing the underlying drift risk.

## Consequences

- A full switch can visibly open the profile menu twice and can briefly move the pointer.
- The implementation is coupled to the English labels and Accessibility structure of tested ChatGPT versions, though relative composer geometry is more robust than absolute coordinates.
- The normal conversation composer is the supported layout. Open-in preview/sidebar behavior remains unverified.
- ChatGPT UI changes require renewed Accessibility-tree and live behavior verification; a label or structure mismatch disables the unsafe path instead of guessing.
- The helper stays local-only and does not need chat content, account credentials, or network access.
- Configuration can express a supported model-and-effort pair that the current ChatGPT UI does not offer; runtime selection then reports the existing typed or partial failure without guessing.

## Supersession condition

Revisit this decision if ChatGPT provides a supported model-selection API or consistently exposes the composer picker and all menu choices as actionable Accessibility elements. Preserve frontmost scoping, final-state verification, and fail-closed behavior in any replacement.
