# ReasonDeck

ReasonDeck is a small macOS menu-bar app for switching model and reasoning settings in ChatGPT and Cursor with keyboard shortcuts you choose.

It is local-only, starts with no shortcuts, and is unofficial. It is not affiliated with or endorsed by OpenAI, Anthropic, Cursor, or Google.

![ReasonDeck settings](docs/settings.png)

## Download

### [Download ReasonDeck 0.1.0 for Mac](https://github.com/thierryskoda/ReasonDeck/releases/download/v0.1.0/ReasonDeck-0.1.0.dmg)

Universal app for Apple silicon and Intel · macOS 14 or later · [release notes and checksum](https://github.com/thierryskoda/ReasonDeck/releases/tag/v0.1.0)

Version 0.1.0 is a prerelease and supports ChatGPT. The current source is ahead of that build and also contains newer Cursor work.

### Install

1. Open the DMG and drag **ReasonDeck** to **Applications**.
2. Open ReasonDeck from Applications. It appears in the menu bar instead of the Dock.
3. In Settings, choose **Allow Accessibility** and **Allow Input Monitoring**, then enable ReasonDeck in the System Settings panes that open.
4. Add a shortcut and choose its model and reasoning effort.

Official binaries are signed with Developer ID and notarized by Apple. Do not install a copy that requires a Gatekeeper bypass or a terminal command.

## What it does

- Creates any number of model-and-effort shortcuts.
- Runs a shortcut only when its supported app is frontmost.
- Passes the same keys through normally in every other app.
- Rejects shortcuts without Command, Option, or Control and prevents duplicates.
- Reports unavailable choices instead of guessing or silently substituting another model.

The current source also includes Cursor's **Next finished session** shortcut. Claude Code switching remains gated until its signed live Accessibility checks pass. Neither change is part of the downloadable 0.1.0 build.

Other adapter code in the development branch is experimental unless a release note explicitly includes it.

ChatGPT models currently recognized by source: 5.6 Sol, 5.6 Terra, 5.6 Luna, 5.5, 5.4, 5.4 Mini, and 5.3 Codex Spark.

ChatGPT efforts currently recognized by source: Extra High, Medium, None, Light, Ultra, High, and Max.

## Requirements and compatibility

- macOS 14 or later
- The English ChatGPT Mac app (`com.openai.codex`)
- The English Cursor Mac app (`com.todesktop.230313mzl4w4u92`) when building the current source
- Accessibility and Input Monitoring permission

ChatGPT support expects a normal conversation with the composer visible and the native **Select model** command (`⌃⇧M`) available. Preview, sidebar, and task layouts are not supported targets.

Cursor support expects an idle Agent or Chat composer with its model chip visible. The current development baseline covers Cursor 3.15.6 and 3.16.29 on macOS 26.5.1. Cursor's server-driven model list can change, so ReasonDeck accepts only exact labels it knows and fails closed on anything else.

Compilation and unit tests are not compatibility proof. Each supported app version needs a signed live check before it is claimed for a release.

## Privacy and safety

- No network implementation, analytics, or account credentials.
- No collection, storage, logging, or transmission of chat or editor content.
- Shortcuts capture the frontmost supported process, then verify its focused window before switching.
- ChatGPT and Cursor recheck that target before actions and verify the final selection.
- Model and effort labels are closed sets in source.
- No fixed screen coordinates.

ReasonDeck stores only shortcut, model, and reasoning preferences in macOS `UserDefaults`. Accessibility is used to find and verify the active app's controls; Input Monitoring is used for the shortcuts you configure.

The switching design is documented in [ADR-001](ADR-001-accessibility-automation.md), [ADR-002](ADR-002-claude-code-desktop.md), [ADR-003](ADR-003-cursor-model-picker.md), and [ADR-004](ADR-004-cursor-unread-navigation.md).

## Troubleshooting

- **Permissions are required:** Use the matching **Allow** action in ReasonDeck Settings, enable the installed app in System Settings, then return to ReasonDeck.
- **Hotkeys do not respond:** Confirm Input Monitoring is enabled. ReasonDeck retries its listener when the app becomes active again; relaunch once if macOS asks.
- **Only the model changes:** The requested effort was unavailable or could not be verified. ReasonDeck reports a partial result instead of rolling the model back.
- **A shortcut will not save:** Include Command, Option, or Control. Escape cancels recording, unmodified Delete clears it, and duplicate combinations are rejected.
- **Cursor's model control is unavailable:** Open the Agents sidebar and leave an idle Agent or Chat composer visible.
- **A model is unavailable:** The account or app no longer exposes the exact saved label. ReasonDeck does not substitute a similar model.
- **Saved shortcuts are invalid:** Open Settings and choose **Reset to Empty**. Invalid persisted configuration stays disabled until you explicitly reset it.

## Build from source

Building requires Xcode with the macOS SDK.

```sh
git clone https://github.com/thierryskoda/ReasonDeck.git
cd ReasonDeck
cp Config/Local.xcconfig.example Config/Local.xcconfig
```

Set `DEVELOPMENT_TEAM` in `Config/Local.xcconfig`, then run:

```sh
swift test
xcodebuild \
  -project ReasonDeck.xcodeproj \
  -scheme ReasonDeck \
  -configuration Release \
  -derivedDataPath build \
  build
open build/Build/Products/Release/ReasonDeck.app
```

Keep the tracked bundle identifier unless you intentionally want a separate development identity and separate macOS privacy grants. Use a consistently signed Release build for live permission testing; the SwiftPM debug executable is not a supported live app identity.

CI runs the tests and an unsigned universal Release build. It has no Apple credentials and cannot publish the app.

## Contributing

Small, focused improvements are welcome. Please open an issue before a large behavior or architecture change.

Run `swift test` before submitting code. Changes to Accessibility targeting, click or key delivery, phase ordering, permissions, signing, or supported model labels also need a signed Release build and a live check in an idle, normal-layout target session. The ADRs above explain the fail-closed constraints that contributions must preserve.

Maintainers can find the release checklist in [docs/RELEASING.md](docs/RELEASING.md).

## Uninstall

Quit ReasonDeck and move it from Applications to the Trash. Saved shortcuts remain available for a later reinstall. To remove them too:

```sh
defaults delete com.thierryai.ReasonDeck
```

## License

[MIT](LICENSE) © 2026 Thierry Skoda
