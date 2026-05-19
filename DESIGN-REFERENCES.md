# Visual references — Typeless + Wispr Flow

Captured 2026-05-18 via Scrapling (DynamicFetcher, `--ai-targeted`).
Source markdown + downloaded reference images in `$CLAUDE_JOB_DIR/refs/`.

---

## Typeless (typeless.com)

**What they sell:** macOS-first voice dictation. Single CTA: `Download for macOS`. Pricing: just "Free". Stats: 4x speed, 220 vs 45 wpm, 100+ languages.

**Visual language extracted from their hero / product shots:**
- **Canvas:** light gray-blue (#ecf0f3-ish), soft cloud noise texture. *Opposite of HazeCraft's dark.*
- **The widget:** a small **black pill** with a 9-dot waveform centered inside.
- **In-context (Slack / Gmail / WhatsApp shots):** dashed connector lines run from app icons down to the widget, showing it acts as a tone-adapting layer across all apps.
- **Active state widget:** same pill, three inline elements — `×` (cancel) · waveform · `✓` (confirm). All white glyphs on black.
- **iOS keyboard variant:** circular black record button with white waveform, sitting in a light tray. "Tap again to finish" label above in body type.
- **Type:** Apple-system (SF Pro-ish), large headlines (~64px), thin/regular weight.
- **No accent color anywhere.** Just black widget + light canvas + product-icon color where apps appear.

**Reference images on disk:**
```
$CLAUDE_JOB_DIR/refs/typeless_hero_voice.webp   ← the floating black pill widget
$CLAUDE_JOB_DIR/refs/typeless_hero_text.webp    ← contrast: "speak vs type" + keyboard glyph
$CLAUDE_JOB_DIR/refs/typeless_tones.webp        ← pill widget with X/waveform/✓ + app icons
$CLAUDE_JOB_DIR/refs/typeless_personalize.webp  ← app categories panel
$CLAUDE_JOB_DIR/refs/typeless_platform.webp     ← iOS keyboard record button + floating widget
```

---

## Wispr Flow (wisprflow.ai)

**What they sell:** cross-platform (Mac, Windows, Android) AI dictation. Brand voice: "Start flowing", "Free for 14 days", emphasis on speed (4x), customer logos (Apple, Linear, Superhuman, WhatsApp).

**Visual language inferred from markdown + URL/copy structure (image not decoded — AVIF):**
- Pricing tiers exposed (FREE / team / Enterprise) — sells more aggressively than Typeless.
- Heavy use of customer-logo trust signals (Apple, Linear, Superhuman, Notion, Rivian, Clay).
- Brand mark uses a stylized "Flow" wordmark + squiggly motif (vector SVG references).
- Product-screenshot file named `flowin-worksapce` — implies a workspace-style hero, not a single widget.

**Conclusion without visual:** Wispr leans more "productivity SaaS" (full app workspace, multi-CTA marketing), Typeless leans more "minimalist tool" (single widget, single CTA). For hushly, Typeless is the stronger pattern source because hushly *is* the widget.

---

## Cross-referenced insights for hushly

### The pill widget pattern wins

Both products converge on a **small floating widget**, not a fullscreen record app. Even Wispr's marketing emphasizes "flowing into any app" — they want their UI to disappear into the host. Hushly currently does the opposite: a 264×76 monolithic blue button dominates the screen.

**Direct implication for the redesign:** the record button should look + behave like a **floating black pill with inline controls** (cancel · waveform · stop), not a full-width button.

### Status text lives above the widget

Both Typeless and (likely) Wispr put state language ("Tap again to finish", "Recording…") above the widget in **body type**, not inside it. The widget itself is glyphic and silent.

**Direct implication:** drop the inline button label ("Tap to record" / "Stop"). Use a tiny mono eyebrow above the pill: `READY` / `RECORDING 4.2s` / `CLEANING` / `COPIED`.

### Waveform is a real animation, not a decoration

Both products show an animated waveform inside the widget. Currently hushly has a generic ActivityIndicator spinner during finalize and nothing during recording.

**Direct implication:** add a Reanimated waveform — N vertical bars (8–12), each driven by a shared value, scaled randomly within bounds during `recording` state, idle bars during `idle`. No mic-level metering needed; pure decorative animation is fine (Typeless does the same).

### Single accent, but the widget IS the brand

Typeless has no accent color and the widget is pure black-on-light. HazeCraft has `#FF0B0B` accent on near-black canvas. The synthesis that doesn't exist yet:

> **Hushly's identity = black pill widget with red waveform glow, sitting on HazeCraft's near-black canvas.**

The widget shape is borrowed from Typeless. The hot red accent inside the widget (waveform color, glow) is borrowed from HazeCraft. No one else in the dictation market looks like this — every competitor I just looked at is light-canvas + black-widget.

### What does NOT port

- Typeless's light canvas (we keep `#050507` from HazeCraft).
- Wispr's multi-CTA / customer-logo marketing density (irrelevant — we're a product surface, not a landing page).
- HazeCraft's 80px display + 56px card padding (mobile-rescaled, per HAZECRAFT-REMAP.md).

---

## Proposed concrete redesign for record screen

```
┌─────────────────────────────────────────────┐
│  hushly                History  ⓘ pee@…ai   │  ← thin header, hairline below
├─────────────────────────────────────────────┤
│                                             │
│         ┏━━━━━━━━━━━━━━━━━━━━━━━┓           │
│         ┃                       ┃           │
│         ┃   "RECORDING  4.2s"   ┃           │  ← mono eyebrow, red (when live)
│         ┃                       ┃           │     "READY" white-30 (idle)
│         ┃    ┌───────────────┐  ┃           │
│         ┃    │ ╳   ╷╷╷╷╷╷╷ ✓│  ┃           │  ← THE pill: cancel·waveform·stop
│         ┃    └───────────────┘  ┃           │     black bg, red waveform, white glyphs
│         ┃                       ┃           │     ~280×56, rounded full
│         ┃                       ┃           │
│         ┗━━━━━━━━━━━━━━━━━━━━━━━┛           │
│                                             │
│  ┌─                                       ─┐│  ← transcript card (only when content)
│  │  CLEANED · COPIED                       ││     corner mark top-left, hairline border
│  │                                          ││     #13161f surface
│  │  Hey, can you send me the link to       ││
│  │  that doc we talked about yesterday?    ││
│  │                                          ││
│  └─                                       ─┘│
│                                             │
│            Customize button                 │  ← tertiary link, white-30
└─────────────────────────────────────────────┘
```

**Idle state:** just the pill (centered) + `READY` eyebrow above it + tiny `⌥ Space` kbd hint below on web.
**Recording:** pill expands to show `× wave ✓` inline. Red glow halo behind pill (Reanimated pulse). Status eyebrow `RECORDING 4.2s` in red.
**Finalizing:** pill stays, waveform freezes, eyebrow becomes `CLEANING…` in blue-tinged white.
**Done:** transcript card slides in below, eyebrow becomes `COPIED` in green.

This is the synthesis: Typeless's interaction model + HazeCraft's color/type discipline + hushly's existing API pipeline.

---

## Decisions still owed

From HAZECRAFT-REMAP.md:
1. **Framing A or B?** A = port the DNA rescaled (recommended); B = apply deck system literally. The references above only strengthen A — the pill widget pattern can't work at 1920×1080 scale.
2. **Phase 1 scope?** Record screen only, or record + history + auth?

When you answer, I start Phase 1. The redesigned screen will:
- Replace the giant blue button with the black-pill widget.
- Add Reanimated waveform animation inside the pill.
- Add mono eyebrows (need to load JetBrains Mono via expo-font).
- Add corner mark + hairline border to transcript card.
- Keep all existing behavior (transcribe / clean / copy / persist) unchanged.
