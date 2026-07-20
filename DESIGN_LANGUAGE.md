# Drive — Design Language (portable spec for the `dash` driving-school dashboard)

This document captures the **Drive** iOS app's visual + interaction language so a
sibling product (`dash`, the B2B driving-school dashboard) can be built in the same
design language. Source of truth is the `DS` enum at the top of
`Drive/Views/HomeView.swift`. All values below are copied from that code.

Each token lists the **SwiftUI source value** and a **web/CSS translation** because
`dash` is expected to be a web dashboard.

---

## 1. Design philosophy

- **Racing-telemetry / instrument-cluster aesthetic.** Dark, precise, data-forward.
  Numbers read like a dashboard readout (monospaced). Restrained color; accent used
  sparingly as a signal, not decoration.
- **Quiet at rest, ignites on press.** No perpetual/looping motion on idle screens
  (better for battery + less distraction). Controls sit calm with a hairline border,
  then flood with accent fill on interaction. Do **not** add `repeatForever` glows or
  breathing pulses without a concrete reason.
- **Touch-down feedback = fill, not scale, for seamed rows.** Scaling a row in a
  grouped panel opens gaps at the hairline seams; instead use a subtle surface-fill
  highlight (`Surface.subtle`) + a soft haptic. Standalone cards may scale to 0.97.
- **Physicality.** Cards have a real fill (`bgCard`), continuous-corner rounding, and
  a 1px stroke. A faint film grain overlays the whole screen for texture.
- **Dark-first**, with a light-mode counterpart for every semantic color.
- **Respect Reduce Motion.** Entry slides collapse to a pure opacity fade; parallax
  tilt disables entirely.

---

## 2. Color tokens

Semantic, theme-aware. Format: `#hex (dark) / #hex (light)`.

| Token | Dark | Light | Use |
|-------|------|-------|-----|
| `bg` | `#0A0A0F` | `#F2F2F7` | App background |
| `bgDeep` / `bgBottom` | `#0A0A0F` | `#E5E5EA` | Gradient bottom / deep background |
| `bgCard` / `card` | `#1A1A1F` | `#FFFFFF` | Card & panel fill |
| `bgGrouped` | `#1A1A1F` | `#FFFFFF` | Grouped list background |
| `accentPrimary` / `accent` | `#1E96FF` (electric blue, glows on black) | `#0A73E5` (deeper for contrast) | Primary action, links, active state |
| `accentSecondary` | `#5BD1E0` (cyan) | — | "Ready" accent (Start button light) only |
| `warning` | `#EC5338` (coral-red) | same | Danger / destructive |
| `scoreGreat` | `#2ED180` (green) | same | Score ≥ 85 |
| `scoreOkay` | `#FFB020` (sharp amber) | same | Score 70–84 |
| `scorePoor` | `#F5665C` (coral) | same | Score < 70 |
| `secondary` | `#8E8E9A` | `#6B6B73` | Secondary text |
| `hairline` | `#161616` | — | 1px dividers/seams (dark) |

**Surfaces** (alpha overlays, theme-aware — white on dark, black on light):
- `Surface.subtle` = 5% (dark) / 6% (light) — touch-down row highlight
- `Surface.weak` = 8% / 8% — chip/pill backgrounds
- `Surface.medium` = 12% / 12% — stronger fills

```css
/* Web translation — dark theme defaults */
:root {
  --bg: #0A0A0F;          --bg-deep: #0A0A0F;
  --bg-card: #1A1A1F;     --bg-grouped: #1A1A1F;
  --accent: #1E96FF;      --accent-secondary: #5BD1E0;
  --warning: #EC5338;
  --score-great: #2ED180; --score-okay: #FFB020; --score-poor: #F5665C;
  --text-primary: #FFFFFF; --text-secondary: #8E8E9A;
  --hairline: #161616;
  --surface-subtle: rgba(255,255,255,0.05);
  --surface-weak:   rgba(255,255,255,0.08);
  --surface-medium: rgba(255,255,255,0.12);
}
@media (prefers-color-scheme: light) {
  :root {
    --bg: #F2F2F7; --bg-deep: #E5E5EA; --bg-card: #FFFFFF; --bg-grouped: #FFFFFF;
    --accent: #0A73E5; --text-primary: #000000; --text-secondary: #6B6B73;
    --surface-subtle: rgba(0,0,0,0.06); --surface-weak: rgba(0,0,0,0.08);
    --surface-medium: rgba(0,0,0,0.12);
  }
}
```

---

## 3. Typography

Three families, each with a clear job. **(Note: an earlier "DIN" note was stale —
the shipped app uses Space Grotesk + SF Mono.)**

| Role | Font | SwiftUI helper | Notes |
|------|------|----------------|-------|
| Display / wordmark / hero | **Space Grotesk Bold** | `DS.Typography.display(size)` → `SpaceGroteskLight-Bold` | Big headings, hero numbers framing |
| Section & card headings | **Space Grotesk Medium** | `DS.Typography.heading(size)` → `SpaceGroteskLight-Medium` | Card titles, screen headings |
| ALL-CAPS metadata labels | **Space Grotesk Medium** | `DS.Typography.label(size)` | Use with letter-spacing (see Tracking) |
| Scores / numeric data | **SF Mono** (system monospaced), weight `.black` default | `DS.Typography.data(size, weight)` | Telemetry readout look. Big scores. |
| Body copy | **System (SF Pro)**, weight `.medium` default | `DS.Typography.body(size, weight)` | Paragraphs, subtitles |

**Tracking (letter-spacing):**
- `label` = 1.5pt — ALL-CAPS labels
- `display` = 2.5pt — wide-tracked display labels

```css
/* Web translation */
--font-display: "Space Grotesk", system-ui, sans-serif;  /* weight 700 */
--font-heading: "Space Grotesk", system-ui, sans-serif;  /* weight 500 */
--font-label:   "Space Grotesk", system-ui, sans-serif;  /* weight 500, uppercase */
--font-data:    ui-monospace, "SF Mono", "JetBrains Mono", monospace; /* weight 800 */
--font-body:    system-ui, -apple-system, sans-serif;    /* weight 500 */

.label   { letter-spacing: 0.12em; text-transform: uppercase; } /* ~1.5pt @ ~12px */
.display-label { letter-spacing: 0.18em; }
.data    { font-variant-numeric: tabular-nums; }
```
Load Space Grotesk from Google Fonts (weights 500 & 700). Use `tabular-nums` for any
changing numbers so they don't jitter.

---

## 4. Spacing & radius scale

**Spacing** (pt → px 1:1 on web): `xs 4 · s 8 · m 12 · l 16 · xl 22 · xxl 34`

**Radius:** `s 10 · m 18 · l 24 · xl 32` — always use **continuous/“squircle”**
corners (SwiftUI `style: .continuous`). On web approximate with generous
`border-radius` plus, ideally, a squircle clip (e.g. an SVG/`@container` superellipse)
for hero cards; plain `border-radius` is an acceptable fallback.

```css
--space-xs:4px; --space-s:8px; --space-m:12px; --space-l:16px; --space-xl:22px; --space-xxl:34px;
--radius-s:10px; --radius-m:18px; --radius-l:24px; --radius-xl:32px;
```

Cards default to **radius-m (18)**. Buttons in the app use 14. Large hero panels use l/xl.

---

## 5. Component recipes

### Card / panel (`physicalCard`)
- Fill `bgCard`, continuous corners (default radius-m = 18).
- 1px stroke (`cardStroke`, a low-alpha white/black hairline).
- Pressed state (standalone cards only): `scaleEffect 0.97`, spring
  `response 0.2, dampingFraction 0.75`.
```css
.card {
  background: var(--bg-card);
  border: 1px solid var(--surface-weak);
  border-radius: var(--radius-m);
  padding: var(--space-l);
}
.card:active { transform: scale(0.97); transition: transform .2s cubic-bezier(.2,.8,.2,1); }
```

### Nav / list row (`PremiumCardLink`)
- HStack: leading icon (Phosphor, `secondary` color, 16pt in a 20pt box) ·
  title (`heading(16)`, primary) + subtitle (14 regular, `secondary`) · Spacer ·
  trailing `caret-right` chevron.
- `minHeight 64`. Touch-down: fill with `Surface.subtle`, `easeOut 0.18` — **no scale**
  (preserves hairline seams). Add a soft haptic on devices.

### Primary button (`StartDriveButton` — "ignites on press")
- **At rest:** transparent/`Surface.subtle` fill + 1px `accent` border at ~55% opacity,
  accent-colored label. Radius 14.
- **Pressed:** floods to solid `accent` fill, white label, `scale(0.97)`,
  border opacity → 0. Driven by a press gesture, animated, not a hover.
```css
.btn-primary {
  background: var(--surface-subtle);
  border: 1px solid color-mix(in srgb, var(--accent) 55%, transparent);
  color: var(--accent);
  border-radius: 14px; padding: 12px 22px; font: 600 16px var(--font-heading);
  transition: all .18s ease-out;
}
.btn-primary:active { background: var(--accent); color: #fff; border-color: transparent; transform: scale(0.97); }
```

### Chip / pill
- `Surface.weak` fill, Capsule shape, label font, often an icon + count.

### Grain overlay (`GrainOverlay`)
- ~1% pixel coverage of 1px white dots at 1.5–4% opacity, `blendMode .overlay`,
  non-interactive, full-screen. Gives the dark UI a film texture.
- Web: a tiled noise PNG or SVG `feTurbulence` at very low opacity with
  `mix-blend-mode: overlay; pointer-events: none;` over the app shell.

### Icons
- **Phosphor Icons** (`fill` weight in most places). Web: use `@phosphor-icons/react`
  or `@phosphor-icons/web`. Common icons in app: `caret-right`, `car`, `sparkle`.

---

## 6. Score color & grade mapping (reuse verbatim if `dash` shows scores)

```
score >= 85           → scoreGreat (#2ED180)
70 <= score < 85      → scoreOkay  (#FFB020)
score <  70           → scorePoor  (#F5665C)
```
Letter grades: `95+ A+ · 90 A · 85 A− · 80 B+ · 75 B · 70 B− · 65 C+ · else C`.
Keep these thresholds identical so a student's score reads the same in both products.

---

## 7. Motion principles

- **Entry choreography:** opacity fade + small `offset(y)` slide, staggered. Under
  Reduce Motion the slide collapses to 0 (fade only).
- **Springs:** press feedback `spring(response 0.2, dampingFraction 0.75)`.
- **Numeric transitions:** SwiftUI `.contentTransition(.numericText())` for changing
  scores; on web use a count-up / tabular-nums crossfade.
- **No idle loops.** Parallax tilt (device-motion) is the only ambient motion, and it
  is disabled under Reduce Motion. The dashboard equivalent: avoid auto-playing
  background animation; reserve motion for state changes and data updates.
- Honor `prefers-reduced-motion` on web exactly as the app honors Reduce Motion.

---

## 8. Shared-domain note

The Drive app already contains `SchoolManager` / `SchoolBannerView` for linking a
student to a driving school. The `dash` dashboard is the school-facing counterpart —
keep entity names, score semantics, and badge/grade language consistent between them
so data presented to instructors matches what students see.

---

_Generated from `Drive/Views/HomeView.swift` (`DS` enum) on 2026-06-28. If the DS
tokens change, regenerate this file — the code is the source of truth._
