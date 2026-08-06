# ChatGPT Profile Keys

ChatGPT Profile Keys is a small macOS menu-bar utility for switching the active ChatGPT conversation with keyboard shortcuts you configure.

![Profile settings](docs/settings.png)

This is a source-first beta. There is no signed or notarized download yet. The project is unofficial and is not affiliated with or endorsed by OpenAI.

## How it works

The app starts with no shortcuts. Open **Settings**, choose **Add Shortcut**, click **Set Shortcut**, and type the keyboard combination you want. Then choose its model and reasoning effort. Add as many entries as you need, edit any combination by recording it again, or remove an entry with its trash button.

Every shortcut must include Command, Option, or Control. This prevents an ordinary typing key from being intercepted. Duplicate combinations are rejected.

Shortcuts are intercepted only when ChatGPT is frontmost. In every other app they pass through unchanged. Menu actions and shortcuts resolve the same current settings at the moment they run.

## Requirements

- macOS 14 or later
- Xcode with the macOS SDK
- The English ChatGPT Mac app (`com.openai.codex`)
- Accessibility permission for inspecting and selecting the active composer controls
- Input Monitoring permission if macOS requests it for global shortcuts

The current compatibility baseline is ChatGPT Mac `26.727.51351`, using the normal conversation layout with the composer visible. Preview and sidebar layouts are not supported.

## Quick start

1. Create a local signing file:

   ```sh
   cp Config/Local.xcconfig.example Config/Local.xcconfig
   ```

2. Edit `Config/Local.xcconfig` with your Apple development team and a bundle identifier you will keep stable.
3. Test and build:

   ```sh
   swift test
   xcodebuild \
     -project ChatGPTProfileKeys.xcodeproj \
     -scheme ChatGPTProfileKeys \
     -configuration Release \
     -derivedDataPath build \
     build
   open build/Build/Products/Release/ChatGPTProfileKeys.app
   ```

4. Use the menu-bar switch icon to grant permissions, then quit and reopen the signed Release app if macOS asks.

Keep the team, bundle identifier, and signing identity stable. macOS privacy grants are tied to the app's designated signing identity. Do not use the SwiftPM debug executable for live permission testing.

CI runs tests and an unsigned Release build. It receives no Apple credentials and does not publish an app.

## Configuration

Each entry has an editable keyboard combination and exact model and effort choices. Arbitrary model or effort text remains deliberately unsupported because these labels are used to validate Accessibility targets.

Supported models: 5.6 Sol, 5.6 Terra, 5.6 Luna, 5.5, 5.4, 5.4 Mini, and 5.3 Codex Spark.

Supported efforts: Extra High, Medium, Light, Ultra, High, and Max.

ChatGPT may not offer every combination in every account or conversation. If the model succeeds but the effort is unavailable, the helper reports a partial result and does not roll the model back.

If saved configuration is corrupt, switching and editing are disabled until you explicitly choose **Reset to Empty**. The app does not silently guess or repair mappings.

## Privacy and safety

The app has no network implementation. It does not request account credentials and does not collect, store, log, or transmit chat content. It stores only your shortcut, model, and reasoning preferences in `UserDefaults`.

The switching path fails closed. It acts only after confirming that ChatGPT is frontmost and the normal composer profile control, expected row or item, and resulting title can be verified. It prefers Accessibility actions. When Chromium exposes only a framed control, it can use a validated composer-relative pointer click and immediately restores the pointer. It never stores fixed screen coordinates.

Model is applied before effort because selecting a model closes and rebuilds ChatGPT's menu. Already-selected phases are skipped. See [ADR-001](ADR-001-accessibility-automation.md) for the safety rationale.

## Verify a switch

1. Open an idle normal-layout ChatGPT conversation with the composer visible.
2. Choose a configured entry from the helper menu and confirm the composer title matches both values.
3. Repeat with its recorded keyboard shortcut.
4. Bring another app frontmost and confirm the same key combination passes through unchanged.

Two visible menu interactions are expected when both values change. A brief pointer movement can appear during the validated geometry fallback.

## Troubleshooting

- **Profile actions are disabled:** grant Accessibility permission, quit the helper, and reopen the same signed Release app. Use **Retry Hotkeys** if Input Monitoring was just granted.
- **Only the model changes:** the effort was unavailable or could not be verified. The status explains the partial result.
- **A shortcut will not record:** include Command, Option, or Control. Escape cancels recording; unmodified Delete clears the current combination.
- **A shortcut is rejected:** another entry already uses the same combination.
- **Saved shortcuts need reset:** open Settings and choose **Reset to Empty**.
- **A ChatGPT update breaks switching:** treat that UI as incompatible until its Accessibility tree and relative composer geometry are revalidated. Do not replace the targeting with fixed coordinates.
- **Code-sign verification reports a trust error:** verify that Xcode sees a valid Apple Development identity and that its certificate chain is trusted in the login keychain.

## Remove

Quit the helper, delete its app bundle, remove it from Accessibility and Input Monitoring in System Settings, and delete its preference domain if you also want to remove saved profile choices. The preference domain matches the bundle identifier configured in `Config/Local.xcconfig`.

## License

MIT. See [LICENSE](LICENSE).
