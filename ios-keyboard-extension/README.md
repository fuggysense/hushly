# hushly iOS Keyboard Extension

Lets users dictate hushly-style cleanup into **any iOS text field** (Messages,
Mail, Notes, Slack, third-party apps) by enabling hushly as a system keyboard.

## What's here

```
ios-keyboard-extension/HushlyKeyboard/
├── KeyboardViewController.swift   # Main extension — tap-to-record, chunked transcribe, /clean, insertText
└── Info.plist                     # NSExtensionPointIdentifier=com.apple.keyboard-service, RequestsOpenAccess=YES
```

## Why this isn't in Expo Go

iOS keyboard extensions are a separate *target* in the Xcode project, packaged
alongside the main app but with their own bundle ID, entitlements, and lifecycle.
Expo Go is a *single* prebuilt host — it can't host arbitrary native targets.
Running the keyboard requires a custom dev client built with EAS Build.

## Build steps (one-time)

```bash
# 1. Apple Developer account ($99/yr) and Xcode 15+ installed.

# 2. Prebuild the iOS project (generates ios/ folder).
cd "/Users/jerel/CC Apps/hushly"
npx expo prebuild --platform ios

# 3. Open the workspace in Xcode.
open ios/hushly.xcworkspace

# 4. In Xcode: File → New → Target → Custom Keyboard Extension.
#    Name: HushlyKeyboard
#    Bundle ID: app.hushly.keyboard
#    Embed in Application: hushly

# 5. Replace the auto-generated files with the ones in this folder:
#    cp ios-keyboard-extension/HushlyKeyboard/* ios/HushlyKeyboard/

# 6. Add App Group entitlement to BOTH targets (main app + extension):
#    Signing & Capabilities → + Capability → App Groups
#    Add: group.app.hushly

# 7. In the extension's Build Settings, set:
#    iOS Deployment Target: 15.0+
#    Swift Language Version: 5.0+

# 8. EAS Build for a real device test:
npm install -g eas-cli
eas login
eas build --profile development --platform ios
# Install the resulting .ipa on your iPhone (Apple Configurator or TestFlight)

# 9. On the iPhone:
#    Settings → General → Keyboards → Add New Keyboard → hushly
#    Then tap hushly → toggle "Allow Full Access" ON (required for network)
```

## How it works

1. User holds a text field in any app.
2. Switches to hushly keyboard via the globe key.
3. Taps "Tap to record" → mic captures audio in 2.5s chunks.
4. Each chunk POSTs to `https://hushly.genflos.com/transcribe` → partial transcript appended.
5. Tap "Tap to stop" → drops un-rotated final segment, calls `/clean` for OpenAI cleanup.
6. `UITextDocumentProxy.insertText(cleaned)` writes directly into the host app's text field.

No clipboard hop. No app-switch. No copy/paste step.

## Auth (not yet wired)

The current scaffold makes anonymous calls to the API. To attribute transcripts to a logged-in user from the keyboard, share the Hushly session token between the main app and the extension via the App Group:

```swift
// In the main app, after sign-in:
let groupDefaults = UserDefaults(suiteName: "group.app.hushly")
groupDefaults?.set(session.accessToken, forKey: "hushly_access_token")

// In KeyboardViewController, when calling /persist:
let token = UserDefaults(suiteName: "group.app.hushly")?.string(forKey: "hushly_access_token")
req.setValue("Bearer \(token ?? "")", forHTTPHeaderField: "Authorization")
```

Add this as a Phase 2 task after the basic keyboard works.

## Caveats

- **Password fields** and **secure inputs** block all custom keyboards.
- Some sandboxed apps (Mail.app in some configs) may delay text insertion.
- Apple rejects keyboard extensions during App Store review if "Full Access" is required without a clear in-app explanation. Add a settings screen in the main app that explains why it's needed.
- Mic permission UI is shown by iOS the first time the keyboard records — there is no way to pre-prompt.
