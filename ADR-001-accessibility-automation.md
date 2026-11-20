# ADR-001: Accessibility automation strategy

- Status: Accepted
- Scope: ChatGPT model-and-effort selection in the macOS helper

For first checks, live log capture, and candidate verification, start with [Diagnose ChatGPT shortcuts](README.md#diagnose-chatgpt-shortcuts).

## September 2026 composer and Power picker

ChatGPT 26.901.31953 exposes the task composer as an AXTextArea and AXPopUpButton with the same immediate parent, approximately 28 levels below the focused window. Its Control-Shift-M command can open an inline model list rather than the older native Model/Effort picker. GPT-6 Astra is a closed model value; an unrecognized current model must never be silently replaced.

ChatGPT 26.1021.31345 also exposes the exact model-and-effort popup beneath one visible wrapper sharing the input's immediate parent. Accept that one extra edge within the input's own branch; another text area in an adjacent branch must not claim it, and deeper or duplicate controls remain unsupported.

Prefer the modern adapter when exactly one such composer is proven. Bound traversal to 40 levels and 3,500 nodes, retain the parent edges from that traversal rather than unstable AXParent references, and prune input descendants without reading their values. Only classify exact control labels and static text within verified picker structures; do not aggregate transcript text into ancestor labels.

The current layout has three states: a compact portal of exact model menu items while the composer popup is expanded, a group of exact model buttons immediately adjacent to the composer, and the Power popover. Model rows require a unique structural group containing at least two distinct known models. Duplicate rows or groups are failures. The Power popover requires one Power menu item, its owned Select model action, an exact model/effort status with valid announced bounds, and the documented Left/Right keyboard instructions. Reacquire these controls after every action.

The installed app source maps the Power presentation labels Standard to Medium and Extended to High; other efforts retain their exact labels. Parse the complete status, including its bounded position and total. Focus the exact Power item and wait for Accessibility to report that same focused element before delivering one documented Left/Right adjustment. Verify the same model, the same total, an adjacent announced position, and the newly observed effort after every step. Stop on missing focus, unknown labels, no progress, overshoot, or context change. This is semantic adjustment of a named control, not arrow-count model-menu navigation. Never infer an effort from an absolute slider index.

Preserve model-before-effort, final observed selection, partial-failure reporting, and captured-window revalidation. Cleanup may send at most three Escapes, proving a modern picker remains open before each, then restore only the original captured input focus. The older native picker contract below remains the fallback for layouts that do not expose the modern composer; the modern path does not fall back midway through a transaction.

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

Frontmost scoping is mandatory in the switching interface. Callers cannot opt into targeting a background process. The shortcut collection is dynamic and starts empty. Keyboard combinations must be unique, while model and effort selections remain configurable only from closed exact-label sets. Persisted configuration is read per entry and per assignment: what this build can still honor is kept and what it cannot is dropped. Dropping is not repair — a retired model or effort is removed, never substituted with another — so the closed-label guarantee holds while a retired feature no longer destroys unrelated shortcuts. What remains is visible in Settings, which is where a user checks what a shortcut does. Data that is not a configuration, or one written by a newer build, still disables switching until an explicit reset.

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
- Modern task composers with the direct sibling or single-wrapper input/popup contract are supported alongside the older native conversation picker. Open-in preview/sidebar behavior remains unverified.
- ChatGPT UI changes require renewed Accessibility-tree and live behavior verification; a label or structure mismatch disables the unsafe path instead of guessing.
- The helper stays local-only and does not need chat content, account credentials, or network access.
- Configuration can express a supported model-and-effort pair that the current ChatGPT UI does not offer; runtime selection then reports the existing typed or partial failure without guessing.

## Live verification of the modern path

On macOS 26.5.1 with ChatGPT 26.901.31953, the installed Developer ID signed ReasonDeck 0.2.6 build 10 passed the saved Command-Shift-1 (Sol/Light) and Command-Shift-2 (Sol/High) shortcuts through its event tap. Verified cases included model plus effort changes, effort-only changes, an already-applied request, and starts with the inline list, Power popover, and compact list already open. The same adapter also passed Astra/High to Sol/High and back, and Sol High to Extra High and back. A foreground-app change aborted a live attempt. Intel is included in the universal build but was not tested on Intel hardware; the older native layout remains unit-tested rather than reverified on this app version.

On macOS 26.5.1 with Codex 26.924.22138, a Developer ID signed ReasonDeck 0.5.0 diagnostic candidate captured repeated model-change requests and identified the frontmost Codex process. The focused window published only 14 Accessibility nodes: zero text areas, popups, or recognized model controls. The native `Control-Shift-M` attempt timed out with the same 14-node tree and `picker_not_found`. A bounded candidate also traversed `AXVisibleChildren` alongside `AXChildren` and `AXContents`, with no improvement. Codex returned unsupported/not-implemented errors for the app-level web Accessibility preparation attributes. The user-visible GPT-6 Sol Power panel and model list therefore do not establish an actionable Accessibility contract. These observations distinguish this failure from shortcut capture, installation, and permission setup; they apply only to the tested version and session. Keep this version fail-closed; do not add screen coordinates, menu positions, or unverified keyboard actions as a fallback. Before claiming support for a later Codex version, confirm that its Accessibility tree exposes one owned composer and exact picker controls, then prove model and effort changes plus final-state read-back with a signed build in an idle normal-layout session.

On macOS 26.6.2 with ChatGPT 26.1021.31345, a locally Apple Development signed ReasonDeck 0.5.0 build 21 candidate passed the saved Command-Shift-1 (GPT-6.1 Sol/Extra High) and Command-Shift-2 (GPT-6.1 Sol/Light) shortcuts after accepting the single-wrapper composer relationship. Both completed with verified final selections; cleanup logged no focus-restoration error, and the user confirmed both visible effort changes. This check covers those effort transitions on the current model; it does not certify model changes, every available model, Intel hardware, or a published release artifact.

## October 2026 regression findings

This was a refinement of the composer ownership contract, not a change to the safety boundary or Power adjustment mechanism. The failure was captured before the fix, reduced to a regression test, and checked again through the installed signed app. Temporary diagnostic probes were removed after diagnosis. The durable evidence below does not depend on retaining a `/private/tmp` log or this conversation.

| Finding | What the investigation established | Where to start next time |
| --- | --- | --- |
| The model catalog and Settings had fallen behind the app | `957e278` added recognition for the new model labels; `fbdf606` removed retired Settings choices and preserved unrelated saved assignments. These changes alone did not repair the later composer-structure failure. | Exact model and effort enums, control-label classification, and per-assignment decoding; avoid a second Settings-only model list. |
| Installed files and the running app could differ | Updating an app bundle did not replace the process serving Settings and shortcuts. | The executable path and source commit, followed by an explicit relaunch of the installed copy. |
| Permission problems and picker problems were separate | After repairing refused Accessibility/Input Monitoring grants, real shortcuts reached `captured`/`dispatched` but still ended in `picker_not_found`. Rebuilding with a stable identity and relaunching retained readiness. | Runtime permission state and designated requirement first; once capture works and permissions are ready, inspect the AX contract. |
| Preparation errors did not prove missing controls | `manualError=-25205 enhancedError=-25208` appeared before both failed and successful transactions. Some failed captures contained hundreds of controls. | Actual control counts and relationships; do not keep retrying unsupported preparation attributes as the proposed fix. |
| One capture did not expose the intended input | A diagnostic snapshot had zero text areas; another later snapshot exposed two. The latter included one uniquely owned model control. | Exact target version, captured window, and focused message field; distinguish a missing input from an ambiguous composer. |
| A panel opening was insufficient proof | Modern-composer discovery failed and the legacy Control-Shift-M path opened UI whose old Model/Effort contract could not be verified. | Determine which adapter path was selected before changing Power actions or adding keyboard steps. |

### Minimal structural evidence and fix

The failing 26.1021.31345 snapshot had 1,510 nodes, two visible `AXTextArea` controls, and one recognized `AXPopUpButton` carrying GPT-6.1 Sol/High. The relevant traversal edges were:

```text
shared ancestor
├── input branch A
│   └── text area 861
└── input branch B (829)
    ├── text area 866
    └── visible wrapper (867)
        └── model-and-effort popup (877)
```

The node IDs identify that captured snapshot only. The earlier direct-sibling rule rejected popup 877 for input 866, so the transaction selected the legacy path and failed in about 3.4 seconds. `0e7166e` accepts the single visible wrapper within the input's own parent, while retaining exact labels, an actionable popup, one unique composer, captured-window validation, and fresh read-back after each action. It does not search arbitrary common ancestors or aggregate transcript text.

In [ChatGPTSurfaceTests.swift](Tests/ChatGPTSurfaceTests.swift), `chatGPTModernComposerFindsTheWrappedPopupInItsOwnInputBranch` failed with `unsupportedSurface` for both closed and open-picker fixtures before the fix. It passes after the fix; adjacent inputs and duplicate, hidden, or deeper wrappers remain covered. The full suite passed 175 tests before the successful signed live check above. Completed events reported GPT-6.1 Sol/Extra High success in about 2.1 seconds and GPT-6.1 Sol/Light success in about 2.6 seconds. Those timings are observations, not performance guarantees.

### Preserve permission continuity during development

`d38e7a4` added [scripts/dev.sh](scripts/dev.sh). Its mechanical job is to test, build, compare the installed and candidate designated signing requirements, stage a fresh complete bundle, replace the installed copy, and relaunch that exact path. Keep diagnosis and judgments about changed UI contracts with the maintainer; do not make the updater guess how to repair permissions.

Pin the exact certificate in ignored `Config/Local.xcconfig`, following the [tracked example](Config/Local.xcconfig.example). The same team name alone is insufficient: the updater requires the designated requirements to match. Switching between public Developer ID and local Apple Development signing can require a one-time grant repair. Repeated same-identity development updates should not require removing and reinstalling the app or resetting saved shortcuts.

The updater stages into a fresh bundle because copying with `ditto` directly over the installed directory merges it and can retain deleted resources, invalidating the new signature. Checks on disposable app copies exercised removal of an obsolete resource and restoration of the prior bundle after a forced failure. A failed build or changed signing requirement stops before the running app is touched. See the script for the current rollback and launch checks rather than duplicating them here.

## Supersession condition

Revisit this decision if ChatGPT provides a supported model-selection API. The September 2026 amendment uses the newly exposed actionable composer and named Power control. Preserve frontmost scoping, final-state verification, and fail-closed behavior in any replacement.
