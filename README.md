# ModelKey

ModelKey is a small macOS menu-bar app for switching the active ChatGPT conversation with keyboard shortcuts you choose.

It is local-only, starts with no shortcuts, and is unofficial. It is not affiliated with or endorsed by OpenAI.

![Profile settings](docs/settings.png)

## Download for Mac

Download the latest `ModelKey-<version>.dmg` from [GitHub Releases](https://github.com/thierryskoda/modelkey/releases/latest).

If the release page does not contain a signed DMG and `SHA256SUMS`, the binary release is not ready yet. Do not download repackaged copies from another source.

### Install

1. Open the downloaded DMG.
2. Drag **ModelKey** to **Applications**.
3. Open the app from Applications. It appears in the menu bar instead of the Dock.
4. In the Settings window, grant Accessibility and Input Monitoring when macOS requests them.
5. Choose **Add Shortcut**, record a keyboard command, then select its model and reasoning effort.

Official binary releases must be signed with Developer ID and notarized by Apple. Never install a release that requires a Gatekeeper bypass or a terminal command.

### Homebrew

The custom Homebrew Cask will install the same notarized DMG published on GitHub. After the v0.1 Cask is available:

```sh
brew install --cask thierryskoda/tap/modelkey
```

Direct download remains the primary installation path.

## Requirements

- macOS 14 or later
- The English ChatGPT Mac app (`com.openai.codex`)
- Accessibility permission to find and select the active composer controls
- Input Monitoring permission for app-scoped keyboard shortcuts

The current compatibility baseline is ChatGPT Mac `26.727.51351`, using a normal conversation with the composer visible. Preview and sidebar layouts are not supported.

## Use shortcuts

The app starts with no shortcuts. Open **Settings**, choose **Add Shortcut**, click **Set Shortcut**, and type the keyboard combination you want. Then choose its model and reasoning effort.

You can add as many entries as you need, replace any keyboard command by recording it again, or remove an entry with its trash button. Every shortcut must include Command, Option, or Control. Duplicate combinations are rejected.

Shortcuts run only when ChatGPT is frontmost. In every other app, the same keys pass through unchanged. ChatGPT may not offer every model-and-effort combination in every account or conversation. If the model succeeds but the effort is unavailable, the app reports a partial result and does not guess or roll the model back.

Supported models: 5.6 Sol, 5.6 Terra, 5.6 Luna, 5.5, 5.4, 5.4 Mini, and 5.3 Codex Spark.

Supported efforts: Extra High, Medium, Light, Ultra, High, and Max.

## Why permissions are required

- **Accessibility** lets the app find the model and reasoning controls in the active ChatGPT window, select them, and verify the final title.
- **Input Monitoring** lets the app receive your configured keyboard shortcuts. Ordinary keys are not valid shortcuts, and unrelated apps keep receiving their keys.

The Settings window shows both permission states and links directly to the matching macOS panes. After granting Input Monitoring, choose **Retry Hotkeys** or relaunch the app.

## Privacy and safety

The app has no network implementation. It does not request ChatGPT account credentials and does not collect, store, log, or transmit chat content. It stores only shortcut, model, and reasoning preferences in macOS `UserDefaults`.

The switching path fails closed. It acts only after confirming that ChatGPT is frontmost and the normal composer profile control, expected item, and resulting title can be verified. It prefers Accessibility actions. When Chromium exposes only a framed control, it can use a validated composer-relative pointer click and immediately restore the pointer. It never stores fixed screen coordinates.

Model is applied before effort because selecting a model closes and rebuilds ChatGPT's menu. Already-selected phases are skipped. See [ADR-001](ADR-001-accessibility-automation.md) for the safety rationale.

## Verify a switch

1. Open an idle, normal-layout ChatGPT conversation with the composer visible.
2. Choose a configured entry from the helper menu and confirm the composer title matches both values.
3. Repeat with its recorded keyboard shortcut.
4. Bring another app frontmost and confirm the same key combination passes through unchanged.

Two visible menu interactions are expected when both values change. A brief pointer movement can appear during the validated geometry fallback.

## Update

Download the newer DMG and replace the app in Applications. Keep the bundle identifier and Developer ID identity stable across versions so macOS can associate the app with the same installation. Saved shortcuts are stored outside the app bundle and should remain available after replacement.

Homebrew users can update with:

```sh
brew update
brew upgrade --cask modelkey
```

## Troubleshooting

- **Profile actions are disabled:** Open Settings and grant the permission marked Required. Reopen the same installed app if macOS asks.
- **Hotkeys do not respond:** Grant Input Monitoring, then choose **Retry Hotkeys** or relaunch.
- **Only the model changes:** The requested effort was unavailable or could not be verified. The status explains the partial result.
- **A shortcut will not record:** Include Command, Option, or Control. Escape cancels recording; unmodified Delete clears the current combination.
- **A shortcut is rejected:** Another entry already uses the same combination.
- **Saved shortcuts need reset:** Open Settings and choose **Reset to Empty**.
- **A ChatGPT update breaks switching:** Treat that UI as incompatible until its Accessibility structure is revalidated. Do not replace targeting with fixed coordinates.

## Uninstall

Quit ModelKey and move it from Applications to the Trash. You can also remove it from Accessibility and Input Monitoring in System Settings.

Ordinary uninstall leaves saved shortcuts in place for a later reinstall. To remove those preferences too:

```sh
defaults delete com.thierryai.ModelKey
```

Homebrew users can uninstall the app while keeping preferences:

```sh
brew uninstall --cask modelkey
```

Use `brew uninstall --zap --cask modelkey` only when you also want the Cask's documented app-owned preferences removed.

## Build from source

Building from source requires Xcode with the macOS SDK.

1. Create the ignored local signing file:

   ```sh
   cp Config/Local.xcconfig.example Config/Local.xcconfig
   ```

2. Set `DEVELOPMENT_TEAM` to your Apple development team. Keep the tracked bundle identifier unless you intentionally want a separate development identity and separate macOS privacy grants.
3. Test and build:

   ```sh
   swift test
   xcodebuild \
     -project ModelKey.xcodeproj \
     -scheme ModelKey \
     -configuration Release \
     -derivedDataPath build \
     build
   open build/Build/Products/Release/ModelKey.app
   ```

Use a consistently signed Release build for live permission testing. The SwiftPM debug executable is not the supported live app identity.

CI runs tests and an unsigned universal Release build. It receives no Apple credentials and cannot publish an app.

Maintainers should follow [the release procedure](docs/RELEASING.md).

## License

MIT. See [LICENSE](LICENSE).
