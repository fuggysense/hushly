# GOAL-PLAN — hushly app-wide redesign (HazeCraft × Typeless synthesis)

Locked plan for `/goal` execution. Format follows `plan-for-goal` skill conventions, sequenced per addyosmani `spec-driven-development` + `planning-and-task-breakdown` + `incremental-implementation` discipline.

Companion docs (read in order if you're a fresh agent picking this up):
1. `HAZECRAFT-REMAP.md` — token map + component remap + scope decisions
2. `DESIGN-REFERENCES.md` — Typeless visual analysis + proposed record screen layout
3. `KEYBOARD.md` — iOS keyboard Swift target (out of scope for this goal)

---

## Brief

Replace hushly's current refined-dark blue-accent UI across all three React Native screens with a single, consistent design system that synthesizes HazeCraft's brand DNA (`#050507` canvas, sole `#FF0B0B` accent, JetBrains Mono eyebrows, Inter 300 thin display, industrial corner marks) with Typeless's interaction primitive (a floating black pill widget with an animated waveform replacing the monolithic record button). Behavior is unchanged — every wire from transcribe → clean → copy → persist works identically. The redesign is purely visual + interaction-pattern, no API or schema changes.

## Stack

- Expo SDK 54 (`expo ~54.0.33`), React 19.1.0, React Native 0.81.5
- New Architecture ON, React Compiler experiment ON, typedRoutes ON
- expo-router 6, expo-audio 1.1, expo-haptics 15, **expo-font 14 (already in deps)**
- react-native-reanimated 4.1, react-native-worklets 0.5
- Supabase JS 2.105, Anthropic SDK 0.96, Deepgram SDK 5.2
- No test runner; type-check via `npx tsc --noEmit`; lint via `npm run lint`

**No new dependencies will be added.** All required libraries are already in `package.json`.

## Scope

**3 screens + 1 layout + 1 token module:**

1. `app/_layout.tsx` — load JetBrains Mono + Inter via `expo-font` + `useFonts`, gate render on font load with `expo-splash-screen`
2. `app/(app)/index.tsx` — record screen: replace monolithic blue button with floating black pill widget containing animated waveform; status eyebrow above pill; transcript card with corner mark
3. `app/(app)/history.tsx` — transcript list: same canvas + accent + Mono timestamps; corner-mark row cards; outlined action buttons
4. `app/(auth)/sign-in.tsx` + `app/(auth)/sign-up.tsx` — token swap (canvas + accent + inputs + submit button + link); Inter 300 32px title
5. **New primitives** to extract (kept inline or in new `components/` folder, TBD by implementer):
   - `<Pill />` — the black-pill widget shell
   - `<Waveform />` — 9 Animated.View bars driven by Reanimated 4 (verified pattern below)
   - `<StatusEyebrow />` — Mono uppercase label + dot + value
   - `<TranscriptCard />` — corner-marked surface

**Font assets to add:**

```
assets/fonts/JetBrainsMono-Regular.ttf
assets/fonts/JetBrainsMono-Medium.ttf
assets/fonts/Inter-Light.ttf
assets/fonts/Inter-Regular.ttf
assets/fonts/Inter-Medium.ttf
```

Download from Google Fonts (`fonts.google.com/specimen/Inter`, `fonts.google.com/specimen/JetBrains+Mono`) — OFL-licensed, no attribution required in product.

## Out of Scope

Do NOT touch in this goal:
- The four API routes (`app/transcribe+api.ts`, `clean+api.ts`, `persist+api.ts`, `retry+api.ts`)
- `lib/api.ts`, `lib/auth.tsx`, `lib/supabase.ts`, `lib/settings.ts`, `lib/recorder.web.ts`
- Supabase migrations (`supabase/migrations/*.sql`)
- iOS keyboard Swift target (`ios-keyboard-extension/` — separate track per `KEYBOARD.md`)
- Recording / transcribe / clean / persist pipeline behavior — preserve exactly
- History list pagination, transcript editing, retry logic
- Logo / marketing pages / onboarding flow
- Dark/light mode toggle — app is dark-mode-only by design
- Animation easings beyond what HazeCraft specifies (200ms hover / 600ms reveal / no bouncy)

## Constraints

1. **Web + native parity.** Every visual element must work on iOS, Android, and web from the same JS — no platform-only CSS hacks. The pill widget + waveform must render identically on all three.
2. **No new dependencies.** Use what's already in `package.json`. If you think a new lib is needed, stop and ask.
3. **Type-check clean.** `npx tsc --noEmit` must exit 0 after every phase.
4. **Lint clean.** `npm run lint` must show **no new warnings or errors** beyond the 6 pre-existing warnings (`react-hooks/exhaustive-deps` in `index.tsx:125` + `_layout.tsx:20`, `@typescript-eslint/array-type` x4 in `*+api.ts`). Do not introduce new lint findings.
5. **Behavior preserved.** Manually verify after Phase 4: web `expo start --web` records audio → transcribes → cleans → copies to clipboard → row appears in Supabase. Same on iOS via Expo Go where possible.
6. **Single accent.** The whole UI uses exactly one accent color: `#FF0B0B`. No blue. No green. Status "Copied" eyebrow may use `#22c55e` (HazeCraft's chart-green token) ONLY for the success state — every other affordance is red or neutral.
7. **No `expo-font` config plugin entry in `app.json`.** Use the runtime `useFonts` hook only (verified — plugin is opt-in build-time optimization, not required). Adding it changes family-name resolution and will break style refs.
8. **Phases are sequential.** Do not start Phase N+1 until Phase N's verification passes. Each phase ends with a git commit.

## DoD (Definition of Done)

Every box must be checkable:

- [ ] Five font files live in `assets/fonts/` (3 Inter weights + 2 JetBrains Mono weights).
- [ ] `app/_layout.tsx` uses `useFonts` from `expo-font`, gates render on `loaded || error`, hides splash screen.
- [ ] No font file is referenced in `app.json` `plugins` (runtime-only).
- [ ] All four screen files (`index.tsx`, `history.tsx`, `sign-in.tsx`, `sign-up.tsx`) import a shared `C` token const (canvas/surface/elevated/hairline/accent/accentSoft/textPrimary/textSecondary/textTertiary/textMuted/success) — either inline at top of each file or extracted to `lib/tokens.ts`.
- [ ] Zero references to the old refined-dark colors (`#0a0a0a`, `#141414`, `#0a84ff`, `#ef4444`) remain in any `app/**/*.tsx` or `lib/**/*.tsx`. Grep verifies clean.
- [ ] `<Waveform>` component animates 9 bars with `useSharedValue` + `withDelay(withRepeat(...))`, runs only when `active === true`, settles to flat low height when not.
- [ ] Record button is replaced with a black pill containing inline `× | waveform | ✓` glyphs during recording; idle pill is just the waveform centered.
- [ ] Status text lives **above** the pill, not inside it. Mono 11px, +0.15em tracking, uppercase, color cycles per state (white-30 / accent-red / accent-red / success-green / accent-red).
- [ ] Transcript card has the HazeCraft 8×8 corner mark top-left + hairline border + `#13161f` surface.
- [ ] History row cards adopt the same corner-mark + hairline + surface tokens. Action buttons (Copy / Retry / Delete) are outlined hairline buttons, white-55 text, no colored fills (except Delete text in accent red).
- [ ] Sign-in + Sign-up forms use the new tokens. Submit button is accent red. Inputs use `#1c1c1e`-equivalent surface + hairline border.
- [ ] `npx tsc --noEmit` exits 0.
- [ ] `npm run lint` shows ≤ 6 warnings, 0 errors (same pre-existing 6 as today).
- [ ] `package.json` diff is empty (no new deps).
- [ ] App runs without runtime errors on `expo start --web`.

## Acceptance

Acceptance is **visual + behavioral**, evaluated by Jerel:

1. **Visual** — open the record screen on web. The screen reads as "HazeCraft x Typeless," not "blue refined dark." Specifically: near-black canvas, the pill widget is the only thing on screen with mass, status eyebrow above it uses JetBrains Mono, the transcript card has a tiny corner mark top-left.
2. **Recording state** — tap the pill. Status eyebrow flips to `RECORDING 0.0s` in accent red, waveform animates, soft red glow around pill (Reanimated pulse).
3. **Done state** — tap stop. Status flips to `CLEANING…` (white) then `COPIED` (green). Transcript card slides in below the pill with the cleaned text.
4. **History** — open History tab. Rows feel like the record screen — same surface, same Mono timestamps, same corner mark per card.
5. **Auth** — sign out, see sign-in form. Same canvas + accent red button. No leftover blue.
6. **Behavior** — entire transcribe → clean → copy → persist pipeline works identically to before. Audio uploads to Supabase Storage. Clipboard receives cleaned text.

If any of those six fail, the goal is not done.

## Verification

Run in order at the end of every phase:

```bash
cd "/Users/jerel/CC Apps/hushly"
grep -rn --include='*.tsx' -E '#0a0a0a|#141414|#0a84ff|#ef4444' app/ lib/ && echo "STALE COLOR REFS FOUND" || echo "no stale color refs"
npx tsc --noEmit && echo "TSC OK"
npm run lint 2>&1 | grep -E '(error|warning)' | wc -l   # must be 6
git diff --stat package.json package-lock.json   # must be empty
```

End-state visual smoke:
```bash
npm run web   # open the URL, hit record, verify acceptance steps 1-6
```

## Turn Budget

**Total: 8 turns max.** One per phase + 2 reserve. If a phase blows past its budget, stop and ask Jerel before continuing.

### Phase 1 — Tokens (1 turn)
- Extract `C` const (extend current one in `index.tsx` with new tokens) → either inline in each file or `lib/tokens.ts`.
- Replace every color literal in `app/(app)/index.tsx`, `history.tsx`, `(auth)/*.tsx` with `C.*` references. **Don't yet change components or structure** — pure swap.
- Verify: grep for stale literals, tsc, lint.
- **Commit:** `redesign: swap color tokens to HazeCraft palette`

### Phase 2 — Fonts (1 turn)
- Download 5 font files (3 Inter, 2 JBM) into `assets/fonts/`.
- Modify `app/_layout.tsx` per verified pattern below.
- Apply `fontFamily` to existing Text styles in all four screens (display=Inter-Light, body=Inter-Regular, eyebrow=JetBrainsMono-Regular).
- Verify: app launches, no font-loading errors, no FOUC on web reload.
- **Commit:** `redesign: load Inter + JetBrains Mono via expo-font`

### Phase 3 — Primitives (2 turns)
- Build `<Waveform>` component (see code below).
- Build `<Pill>` component (rounded full container, max ~280×56, accepts left/center/right slots).
- Build `<StatusEyebrow>` (dot + Mono uppercase label).
- Build `<TranscriptCard>` (corner mark + hairline border + surface bg).
- Each primitive ships in its own file under `components/` and gets imported into `index.tsx` first as a smoke test.
- Verify: tsc + lint clean.
- **Commit:** `redesign: extract Pill / Waveform / StatusEyebrow / TranscriptCard primitives`

### Phase 4 — Record screen rewrite (2 turns)
- Replace the giant `btnPrimary` / `btnStop` Pressables in `index.tsx` with `<Pill>` containing `<Waveform active={phase==='recording'} />` and inline `×` / `✓` Pressables during recording.
- Move status text into `<StatusEyebrow>` above the pill.
- Wrap transcript card in `<TranscriptCard>`.
- Keep pulse ring + haptics + keyboard shortcut + edit-button-label flow.
- Verify: acceptance steps 1–3 + 6 pass on web.
- **Commit:** `redesign: record screen — pill widget + waveform + eyebrow status`

### Phase 5 — History screen rewrite (1 turn)
- Adopt `<TranscriptCard>` for each row.
- Mono timestamps. Outlined action buttons (Copy/Retry/Delete).
- Verify: acceptance step 4 passes.
- **Commit:** `redesign: history screen tokens + cards`

### Phase 6 — Auth screen rewrite (1 turn)
- Token swap is mostly done in Phase 1; this phase reshapes inputs and submit button to match the new system. Inter 300 32px title.
- Verify: acceptance step 5 passes.
- **Commit:** `redesign: auth screens tokens + button`

Reserve turns: cleanup, regressions, visual polish based on Jerel's review.

---

## Verified code-shape hand-offs (do not deviate)

### Font loading — `app/_layout.tsx` (sub-agent B verified for SDK 54)

```tsx
import { Stack } from 'expo-router';
import { useFonts } from 'expo-font';
import * as SplashScreen from 'expo-splash-screen';
import { useEffect } from 'react';

SplashScreen.preventAutoHideAsync();

export default function RootLayout() {
  const [loaded, error] = useFonts({
    'JetBrainsMono-Regular': require('../assets/fonts/JetBrainsMono-Regular.ttf'),
    'JetBrainsMono-Medium':  require('../assets/fonts/JetBrainsMono-Medium.ttf'),
    'Inter-Light':           require('../assets/fonts/Inter-Light.ttf'),
    'Inter-Regular':         require('../assets/fonts/Inter-Regular.ttf'),
    'Inter-Medium':          require('../assets/fonts/Inter-Medium.ttf'),
  });
  useEffect(() => { if (loaded || error) SplashScreen.hideAsync(); }, [loaded, error]);
  if (!loaded && !error) return null;
  // ...existing AuthProvider + Gate wraps Stack
}
```

**Reference name in styles:** `fontFamily: 'JetBrainsMono-Regular'` — the `useFonts` key IS the family name. Do NOT use underscored `Inter_400Regular` conventions (those are for `@expo-google-fonts/*` packages, not local TTFs).

### Waveform — verified Reanimated 4 pattern

```tsx
import Animated, {
  useSharedValue, useAnimatedStyle,
  withRepeat, withTiming, withDelay, Easing,
} from 'react-native-reanimated';
import { View } from 'react-native';
import { useEffect } from 'react';

function Bar({ delay, active }: { delay: number; active: boolean }) {
  const s = useSharedValue(0.2);
  useEffect(() => {
    s.value = active
      ? withDelay(delay, withRepeat(
          withTiming(1, { duration: 350, easing: Easing.inOut(Easing.ease) }),
          -1, true))
      : withTiming(0.2, { duration: 200 });
  }, [active, delay]);
  const style = useAnimatedStyle(() => ({ transform: [{ scaleY: s.value }] }));
  return (
    <Animated.View
      style={[{ width: 3, height: 18, marginHorizontal: 2, backgroundColor: '#fff', borderRadius: 2 }, style]}
    />
  );
}

export function Waveform({ active }: { active: boolean }) {
  const delays = [0, 80, 160, 60, 200, 40, 140, 100, 180];
  return (
    <View style={{ flexDirection: 'row', alignItems: 'center', height: 24 }}>
      {delays.map((d, i) => <Bar key={i} delay={d} active={active} />)}
    </View>
  );
}
```

**Why this shape:** `withDelay(withRepeat(...))` gives each bar a phase offset on mount without per-bar timers. `Animated.View` is required for `useAnimatedStyle` to attach (plain `<View>` won't). Reanimated 4 requires New Architecture (already ON in this project).

### Token const shape (extend current `C` from `index.tsx`)

```ts
const C = {
  bg: '#050507',           // HazeCraft canvas
  surface: '#13161f',      // HazeCraft chart-bg (lifted card)
  elevated: '#1a1d27',     // derived mid-step for buttons/chips
  hairline: 'rgba(255,255,255,0.08)',
  textPrimary: '#fff',
  textSecondary: 'rgba(255,255,255,0.55)',  // iconography rule grey
  textTertiary: 'rgba(255,255,255,0.30)',   // meta caption
  textMuted: 'rgba(255,255,255,0.16)',
  accent: '#FF0B0B',
  accentSoft: 'rgba(255,11,11,0.16)',
  success: '#22c55e',
  successSoft: 'rgba(34,197,94,0.16)',
} as const;
```

Type stack (mobile-rescaled from HazeCraft deck values per `HAZECRAFT-REMAP.md`):

| Role | Family | Size | Tracking | Use |
|---|---|---|---|---|
| Display | `Inter-Light` | 32px | -0.03em | Recording timer hero |
| Section | `Inter-Light` | 22px | -0.02em | Screen titles |
| Body | `Inter-Regular` | 15px | 0 | Transcript |
| Eyebrow | `JetBrainsMono-Regular` | 11px | +0.05em uppercase | Section labels (accent red) |
| Meta | `JetBrainsMono-Regular` | 11px | +0.15em uppercase | Status pill, timestamps (white-30) |

---

## Paste-ready `/goal` one-liner

```
/goal Execute hushly app-wide redesign per /Users/jerel/CC Apps/hushly/GOAL-PLAN.md. Read the full plan top-to-bottom, then HAZECRAFT-REMAP.md and DESIGN-REFERENCES.md for visual intent. Work in 6 sequential phases (tokens → fonts → primitives → record → history → auth), commit after each, run npx tsc --noEmit + npm run lint after each phase and STOP if either regresses. No new deps. Use the verified code shapes in GOAL-PLAN.md "Verified code-shape hand-offs" verbatim. DoD checklist must be 100% green before reporting done. Acceptance is visual + behavioral per the six-step check in the plan.
```
