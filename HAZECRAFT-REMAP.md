# HazeCraft → hushly remap plan

Source: `clients/hazecraft/brand/DESIGN/design-system.md` + `ds.css` + chat1.md.
Target: the React Native (Expo SDK 54) app currently at `app/(app)/index.tsx`, `(auth)/*`, `(app)/history.tsx`.

This doc is a **plan for review** — no code is changed by writing it. Read the three flagged decisions at the bottom first; nothing ships until you answer them.

---

## 1. Honest pushback before we commit

The HazeCraft system says, **in its own contract**:

> "Haze Craft is the agency wrapper for Jerel/HazeCraft-owned artifacts: strategy reports, concept packs, prompt-pack galleries, approval pages, internal dashboards, case-study decks, and HazeCraft-branded motion assets. **It is not the default style for client-owned final creative.**"

And the visual DNA was **extracted from a 1UP Sales AI pitch deck**, then ported to HazeCraft. So:

- HazeCraft is a **deck + agency-shell** aesthetic, not a product-UI system.
- Hushly is a product (an AI dictation tool), not a HazeCraft agency deliverable.
- Some of the DNA ports beautifully to a product (`#050507` canvas, single hot accent, monospace eyebrows, restrained type). Other parts will **fight a mobile dictation UI**: 80px display, 56×64px card padding, 1920×1080 reference frame, decorative corner marks, hairline 45° grids.

**Two honest framings:**

- **Framing A — port the DNA, not the deck.** Steal the four principles + accent discipline + type stack + corner-mark motif. Re-scale everything for mobile (display ≤ 32px, padding ≤ 24px, no full-screen grid overlays). The result *feels* like HazeCraft without pretending the phone is a slide. ← my recommendation.
- **Framing B — apply the system literally.** Match the deck. 80px Inter 300 display, 56×64 padding, grid overlay, corner marks on every card. The product will look distinctive but read awkwardly on a 390px-wide screen.

If the goal is **a shared brand language across your agency materials and hushly the product**, Framing A delivers that without breaking the product. Pick A unless you explicitly want the deck look.

---

## 2. Token remap (from `ds.css` → RN `C` const in `app/(app)/index.tsx`)

| Current (refined-dark) | HazeCraft replacement | Notes |
|---|---|---|
| `bg #0a0a0a` | `base #050507` | Slightly deeper, matches HazeCraft `--base`. |
| `surface #141414` | `chart-bg #13161f` | Card surface = HazeCraft lifted-card token. |
| `elevated #1c1c1e` | `#1a1d27` (derived) | Mid-step between chart-bg and brighter; not in HC tokens, derived for buttons/chips. |
| `hairline #262626` | `rgba(255,255,255,0.08)` | Matches `.card-header` border. |
| `accent #0a84ff` | **`#FF0B0B`** | **THE big change** — single hot red replaces blue. |
| `danger #ef4444` | `#FF0B0B` (same) | HazeCraft has no separate danger — accent serves both CTA and stop/record. Recording = same color as primary CTA. |
| `success #22c55e` | accent or chart-green `#10b981` | Status pill "Copied" uses chart-green (functional, not brand). |
| `textPrimary #fafafa` | `#fff` | HazeCraft uses pure white. |
| `textSecondary #a1a1aa` | `rgba(255,255,255,0.55)` | Iconography rule's grey. |
| `textTertiary #71717a` | `rgba(255,255,255,0.30)` | Meta caption. |

**Type stack** — load Inter via `expo-font` + JetBrains Mono. Currently no custom font is loaded. Two files to touch: `app/_layout.tsx` (font loader) + `app.json` (asset bundle).

**Type scale (mobile-rescaled from HazeCraft deck values):**

| Role | HazeCraft (deck) | hushly (mobile) | Use |
|---|---|---|---|
| Display | Inter 300, 80px / -0.04em | Inter 300, 32px / -0.03em | Recording timer hero |
| Section | Inter 300, 32px / -0.03em | Inter 300, 22px / -0.02em | Screen titles |
| Eyebrow | JetBrains Mono 400, 11px / +0.05em / accent | unchanged | Section labels above transcript blocks |
| Body | Inter 400, 13.5–15px / 1.55 | Inter 400, 15px / 1.55 | Transcript text |
| Meta | 11px / +0.15em / white 30% | unchanged | Timestamps, hints |

---

## 3. Component-by-component remap

### Record screen (`app/(app)/index.tsx`)
- **Status pill** → keep, but adopt HazeCraft's `card-meta` style: JetBrains Mono, 11px uppercase, +0.15em tracking. Recording state dot stays `#FF0B0B`.
- **Record button** → primary CTA now `#FF0B0B` solid, Inter 300 17px label, **no gradient overlay** (HazeCraft principle: "glow > drop shadow on dark"). Replace the top-light overlay with a red `glow` box-shadow (~30px blur, 15% opacity).
- **Stop button (recording state)** → same accent, same shape — there is no second brand color, so Stop = Record visually. Distinction is text + status pill, not color.
- **Cancel button** → outlined, hairline border `rgba(255,255,255,0.08)`, no fill, white-55 text.
- **Transcript card** → keep card, change bg to `#13161f`, padding 24px, hairline border. Add **one 8×8 corner mark top-left** (HazeCraft signature). Eyebrow row above content uses JetBrains Mono red.
- **Pulse ring** → keep Reanimated pulse but recolor to accent red glow. HazeCraft's motion principle: ease-out only, no bouncy. Current `Easing.out(Easing.cubic)` already complies.
- **Idle empty state** → replace generic circle glyph with a 24px-stroke microphone icon in white-55, hovering above a Mono eyebrow "READY" in accent red.
- **Account chip** → kill the colored avatar bubble; use a Mono eyebrow with email + "Sign out" link.

### History (`app/(app)/history.tsx`)
- Same token swap. Cards adopt `#13161f` surface + corner mark.
- Row timestamps → Mono meta caption style.
- Action buttons (Copy/Retry/Delete) → outlined hairline buttons, no colored fills. Delete keeps accent red text only.

### Auth (`sign-in.tsx`, `sign-up.tsx`)
- Canvas + accent + hairline inputs. Title → Inter 300 32px. Submit button → accent red. Skip the avatar/account chip patterns (irrelevant pre-auth).

### Keyboard extension (Swift)
- Same remap, separate session. Already documented in `KEYBOARD.md` Gap C.

---

## 4. What ports cleanly, what gets dropped

**Ports cleanly:**
- Four visual DNA principles (industrial precision, single accent, thin type, dark canvas)
- Color tokens (canvas + accent + chart-bg + chart-green for success status)
- Iconography rule (glyph-only color change on press — fits Pressable)
- Motion durations (200ms hover/press, 600ms reveal, 800ms data anim) — already roughly aligned
- Corner mark as recurring product motif (apply sparingly: one per primary card)
- Single-accent discipline (drop the blue + red duality)

**Gets dropped / rescaled:**
- 80px display → 32px max on mobile
- 56×64 card padding → 20×24
- 1920×1080 frame assumption (irrelevant)
- 45° hairline grid overlay (too noisy on a small screen — used only on empty states, if at all)
- Chart palette (no charts in hushly yet)
- TAM/SAM/SOM funnel, phase card, process node, pull quote, stat card (deck patterns, no use here)

---

## 5. References I still want to pull before coding

The directive also said "see how the UI for WhisperFlow and Timeless looks like." Status:

- **Wispr Flow** (wisprflow.ai) — known product, voice dictation. Worth fetching their marketing page + app screenshots for hierarchy + button language reference. **Action**: ctx_fetch_and_index after this plan is approved.
- **Timeless** — ambiguous. There are at least three candidates: (a) timeless.app (an iOS time/calendar app), (b) timelesstech.com (a productivity tool), (c) the user might mean "Tempo" or a different dictation reference. **Question for you** at the bottom.

These references are for cross-checking layout hierarchy + interaction patterns, **not** for stealing visual style — HazeCraft remains the visual base.

---

## 6. Scope phases (so we don't ship a half-redesign)

1. **Phase 1 — Tokens + Record screen.** Replace `C` const, add Inter + JetBrains Mono via `expo-font`, redo `index.tsx`. Single PR. Ship-test on web + iOS.
2. **Phase 2 — History.** Same token sweep + corner mark + Mono timestamps.
3. **Phase 3 — Auth.** Lowest priority (used once per user). Same tokens.
4. **Phase 4 — Keyboard (Swift).** Port to Swift colors + CABasicAnimation glow. Separate target, no JS.

Each phase is one PR, type-check + lint clean, before the next starts.

---

## 7. Three questions before I touch any code

1. **Framing A or B?** (Port the DNA rescaled for mobile, OR apply the deck system literally.) Recommended: A.
2. **What is "Timeless"?** Best guess timeless.app — confirm, or paste the URL you mean.
3. **Phase 1 scope = record screen only?** Or do you want History + Auth in the same pass (bigger PR, more risk, but consistent feel sooner)?

When you answer those, I'll start Phase 1.
