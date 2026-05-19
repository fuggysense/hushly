# hushly keyboard — how it connects

The iOS keyboard extension is the **second consumer** of the same backend the React Native app already uses. It is **not** a port of the app — it's an independent native target that talks to the same `/transcribe` and `/clean` endpoints. This doc maps every wire so you can reason about what's done and what's missing.

---

## 1. Big picture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                            iPhone                                       │
│                                                                         │
│  ┌──────────────────┐         ┌────────────────────────────────────┐   │
│  │  Host app        │  ←──    │  hushly keyboard extension         │   │
│  │  (Notes, Slack,  │  text   │  (separate sandboxed process)      │   │
│  │  Mail, anything) │         │                                    │   │
│  └──────────────────┘         │  • UIInputViewController subclass  │   │
│           ▲                   │  • AVAudioRecorder → m4a chunks    │   │
│           │ UITextDocument-   │  • URLSession → Vercel API         │   │
│           │ Proxy.insertText  │  • Reads JWT from App Group        │   │
│           │                   └────────────────┬───────────────────┘   │
│                                                │                       │
│  ┌────────────────────────────────────────┐   │   ┌──────────────┐    │
│  │  Main hushly app (Expo / React Native) │◄──┴──►│ App Group    │    │
│  │  • Signs user in (Supabase auth)       │       │ UserDefaults │    │
│  │  • Writes JWT to App Group on sign-in  │  jwt  │ group.app.   │    │
│  └────────────────────────────────────────┘       │ hushly       │    │
│                  │                                 └──────────────┘    │
└──────────────────┼─────────────────────────────────────────────────────┘
                   │ HTTPS
                   ▼
        ┌──────────────────────────────────────────┐
        │ Vercel (https://hushly-six.vercel.app)   │
        │   /transcribe → Deepgram Nova-3          │
        │   /clean      → Anthropic Haiku 4.5      │
        │   /persist    → Supabase (JWT-gated)     │
        │   /retry      → Supabase + DG + Haiku    │
        └──────────────────────────────────────────┘
```

**Three independent processes** ever touch the keyboard's world:
1. The **host app** (the thing being typed into) — pure data sink, doesn't know hushly exists. Only contract: `UITextDocumentProxy.insertText(string)`.
2. The **main hushly app** — owns sign-in. Hands the keyboard a JWT via App Group shared storage.
3. The **Vercel backend** — same APIs as the main app; the keyboard is just another client.

Everything else lives **inside the extension's own sandbox**: audio capture, network stack, UI.

---

## 2. The runtime connection flow

What happens when a user taps the record button in any text field anywhere on iOS:

```
[User] long-presses any text field in <host app>
    │
[iOS] shows keyboard picker → user taps "hushly"
    │
[iOS] instantiates KeyboardViewController (subclass of UIInputViewController)
    │
[Extension] viewDidLoad() → setupUI() draws record button + status label
    │
[User] taps record button
    │
[Extension] toggleRecord() → startRecording()
    │   ├─ AVAudioSession.setCategory(.playAndRecord)
    │   ├─ AVAudioApplication.requestRecordPermission() — first time only
    │   ├─ beginSegment() → AVAudioRecorder writes <uuid>.m4a to tmp
    │   └─ chunkTimer fires every 2.5s
    │
[Every 2.5s while recording]
    │   rotateSegment()
    │   ├─ audioRecorder.stop()   ← seals current chunk
    │   ├─ beginSegment()         ← starts next chunk immediately
    │   └─ Task { transcribeChunk(url) }
    │       ├─ POST <m4a bytes> to https://hushly-six.vercel.app/transcribe
    │       ├─ ← { transcript: "..." }
    │       └─ partials.append(transcript)
    │
[User] taps stop
    │
[Extension] stopAndFinalize()
    │   ├─ audioRecorder.stop()
    │   ├─ wait 600ms for in-flight chunks to land
    │   ├─ raw = partials.joined(" ")
    │   ├─ cleanText(raw)
    │   │   ├─ POST { text: raw } to /clean
    │   │   └─ ← { cleaned: "..." }
    │   └─ textDocumentProxy.insertText(cleaned)   ← appears in host app
    │
[Host app] sees text appear in its focused text field
```

Two design choices worth understanding:

**Chunking vs single-shot.** The keyboard transcribes in 2.5s segments *while still recording* — so when the user taps stop, most of the audio is already transcribed and only the cleanup pass is left. The main app does the opposite (one full recording, transcribe at the end) because the app's UX shows the transcript on screen — it can wait. The keyboard can't keep the user waiting, so it parallelizes.

**Drop the last segment.** When stop is tapped, the in-progress un-rotated chunk is discarded (`stopAndFinalize` doesn't transcribe `currentRecordingURL`). This keeps the finalize step under ~2s. Tradeoff: you lose the last 0–2.5s of speech. For dictation the user typically stops *after* finishing a thought, so this is acceptable.

---

## 3. User-facing flow (what they actually see)

```
Day 1 — install
  1. User installs hushly app from App Store / TestFlight.
  2. Opens app → signs in with email + password.
  3. App tells them: "To dictate in any app, enable the keyboard.
     Settings → General → Keyboards → Add New Keyboard → hushly →
     toggle 'Allow Full Access' ON."
  4. User does this once.

Day 2+ — daily use
  1. User opens Slack to message a colleague.
  2. Taps the message field. iOS keyboard appears.
  3. Long-presses the globe key 🌐 → picks "hushly".
  4. Sees: ● Ready · [Tap to record] button · 🌐 (switch back) corner.
  5. Taps record → red button "Tap to stop" · ● Recording 4.2s.
  6. Speaks: "hey can you send me the link to that doc um the one
     we talked about yesterday".
  7. Taps stop → button greys to "…cleaning" for ~1s.
  8. Cleaned text appears in Slack's compose field:
     "Hey, can you send me the link to that doc we talked
     about yesterday?"
  9. User taps Send. Done. No app switch, no clipboard, no paste.
```

Error states the user can hit:
- **Full Access disabled** → status shows `Enable Full Access in Settings`. Recording is blocked because the network would fail anyway.
- **Mic permission denied** → status shows `mic permission denied`. User has to enable in Settings → hushly → Microphone.
- **No speech detected** → status shows `no speech`, nothing inserted.
- **Network failure** → currently fails silently per chunk (acceptable for a chunk to drop); final cleanText falls back to inserting the raw uncleaned transcript instead of nothing.
- **Inside a password field** → keyboard is blocked by iOS; standard system keyboard appears instead. Not a hushly bug.

---

## 4. What's already wired

| Wire | Status |
|---|---|
| Tap-to-record → AVAudioRecorder writes m4a | ✅ working |
| 2.5s chunked rotation + parallel transcribe | ✅ working |
| POST to `/transcribe` (Deepgram proxy) | ✅ working |
| POST to `/clean` (Anthropic Haiku proxy) | ✅ working |
| `UITextDocumentProxy.insertText` into host app | ✅ working |
| Globe-key keyboard switcher (`handleInputModeList`) | ✅ working |
| Info.plist: `NSExtensionPointIdentifier=com.apple.keyboard-service` | ✅ |
| Info.plist: `RequestsOpenAccess=YES` (required for network) | ✅ |
| Info.plist: `NSMicrophoneUsageDescription` (required for mic) | ✅ |

---

## 5. What's NOT wired yet (the actual work)

### Gap A — Extension target isn't in the Expo prebuild

The Swift files live at `ios-keyboard-extension/HushlyKeyboard/` — **outside** the Expo-generated `ios/` folder. Today, the workflow is:

1. `npx expo prebuild --platform ios` (regenerates `ios/`)
2. Open `ios/hushly.xcworkspace` in Xcode
3. **Manually**: File → New → Target → Custom Keyboard Extension
4. **Manually**: copy Swift files into the new target
5. **Manually**: add App Group entitlement to both targets

**This is brittle.** Every `expo prebuild` blows away `ios/` and you have to redo steps 3–5. The fix is one of:

- **Option 1 — Expo config plugin** (correct): write a custom plugin in `plugins/` that registers the extension target during prebuild. The `plugins/` directory already exists empty — it's the intended home. The plugin would:
  - Add a new `PBXNativeTarget` for `HushlyKeyboard` in the .pbxproj
  - Copy the Swift + Info.plist into `ios/HushlyKeyboard/`
  - Add `App Groups` entitlement to both targets
  - Wire signing identifiers

- **Option 2 — never re-prebuild** (lazy): treat `ios/` as a checked-in artifact, do the manual setup once, commit it. Loses the benefit of `app.json` config plugins but is fine for a single-developer project.

For a one-person ship-it-fast path, **Option 2** is acceptable. For a project that will see more contributors or more Expo plugin additions, **Option 1** earns its keep.

### Gap B — Auth sharing (App Group + JWT propagation)

The keyboard makes anonymous calls today. Calls to `/transcribe` and `/clean` are anonymous-friendly (no auth required), so this works. But:

- `/persist` requires a Bearer JWT — keyboard transcripts therefore **never get saved to history**. They insert into the host app and vanish.
- Usage events can't be attributed to a user → no rate-limiting, no per-plan quota enforcement.

To fix this:

```
[Main app, after sign-in]                    [Keyboard, on every request]

let g = UserDefaults(suiteName:               let jwt = UserDefaults(
  "group.app.hushly")                           suiteName: "group.app.hushly"
g?.set(session.accessToken,                   )?.string(forKey: "supabase_jwt")
       forKey: "supabase_jwt")
                                              req.setValue(
                                                "Bearer \(jwt ?? "")",
                                                forHTTPHeaderField:
                                                "Authorization")
```

Required setup:
1. Enable `App Groups` capability in **both** targets (main app + keyboard extension) in Xcode → Signing & Capabilities.
2. Add the same group ID to both: `group.app.hushly`.
3. From RN side, write the JWT via a tiny native module or use `expo-secure-store` with shared keychain access group (cleaner than UserDefaults; survives iOS auth refreshes better).
4. From Swift side, read on every request. Refresh logic: if `/persist` returns 401, the JWT expired — keyboard can't refresh it itself (no Supabase SDK), so it should silently drop persistence and rely on the main app being opened to refresh.

### Gap C — Visual design parity

The current keyboard UI is the SDK starter shape: a single blue button + a status label. The main app just got a refined-dark redesign. To match:

- Color tokens from `app/(app)/index.tsx` (`C.bg`, `C.accent`, `C.danger`, etc.) ported to `UIColor` constants in Swift.
- Status pill (rounded UIView + dot + label) replacing the bare `UILabel`.
- Pulse ring around the record button via `CABasicAnimation` on `transform.scale` + `opacity`.
- Haptics via `UIImpactFeedbackGenerator(style: .medium)` on tap.
- Keep the button width tight — keyboard height is ~280pt, can't fit the app's 76pt button + transcript card.

Cost estimate: ~200 lines of additional Swift, one editing session. No new dependencies.

---

## 6. Ship checklist

What needs to happen before the keyboard is usable by real users:

- [ ] Decide on prebuild integration: write Expo config plugin **or** commit `ios/` and do manual setup once
- [ ] Apple Developer account + signing identities configured
- [ ] EAS Build profile for the keyboard target (`eas.json` `development` profile)
- [ ] App Group `group.app.hushly` enabled on both targets
- [ ] JWT write from main app on sign-in (one-line change in `lib/auth.tsx`'s `onAuthStateChange`)
- [ ] JWT read in `KeyboardViewController` before any authed API call
- [ ] In-app settings screen explaining why "Full Access" is needed (Apple rejects extensions without this)
- [ ] Visual redesign in Swift to match the app's refined-dark language
- [ ] TestFlight build distributed to at least one real device for testing — simulators don't fully exercise the keyboard switcher
- [ ] App Store submission with Full Access justification in the review notes

---

## 7. References

- **Swift extension code**: `ios-keyboard-extension/HushlyKeyboard/KeyboardViewController.swift`
- **Extension Info.plist**: `ios-keyboard-extension/HushlyKeyboard/Info.plist`
- **Build setup**: `ios-keyboard-extension/README.md`
- **Backend pipeline doc**: `CLAUDE.md` → "API routes" section
- **Apple docs**: [Custom Keyboard Extension Programming Guide](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Keyboard.html)
