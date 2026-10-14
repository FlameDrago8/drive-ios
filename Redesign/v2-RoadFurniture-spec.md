# Drive v2: "Road Furniture"

Definitive design spec. It sits on top of the v1 canvas, which stays untouched as the baseline. v2 boards are new files: `v2-Main.dc.html`, `v2-Today.dc.html`, `v2-Report.dc.html`, `v2-Drives.dc.html`, `v2-Progress.dc.html`, `v2-HUD.dc.html`, `v2-Parked.dc.html`, `v2-Share.dc.html`, `v2-DriverCard.dc.html`, `v2-Surfaces.dc.html`, `v2-Motion.dc.html`.

---

## 1. Name and thesis

**Road Furniture.** "Road furniture" is the traffic-engineering term for signs, paint, posts and markers. Flighty earned its award by borrowing a language travellers already read under stress: airport signage, gate badges, departure boards. Drive borrows road furniture. Every Drive user has just memorised it for the permit test. In that system shape carries meaning: an octagon means stop, a diamond means warning, a shield means a route. v2 keeps v1's stock iOS chassis exactly as it is. On top of it, v2 makes road furniture the app's only ornament, and each family has one job:

- **Plates** say *what kind of thing happened*: coaching categories, events, badges.
- **Paint** says *how it went*: the lane-line strip, painted streak days, diagram roads.
- **Shields and posts** say *where and how far*: numbered routes, milestones.
- **Papers** say *who you are*: the Driver Card and the Logbook.
- **Your car** is the only character. It rides the strip while you drive, moves only when data moves, and parks on a P at the end.

The grey "Focus" lozenge becomes a yellow warning diamond, the one yellow object in the app. It is handed to you after a drive, carried into the car, and checked when you park: "Job retired. Two drives with 0 hard starts (was 3)."

Everything is flat, rimmed and texture-free. Color still means status. Motion happens once per event and never at rest.

---

## 2. What changes from v1, and what stays

**Changes**
- Focus chip → **Focus Sign + "Your one job" loop**: set, carried, checked, retired.
- YouTube-style play chips → **moment tokens**: marker, strip excerpt, clock time.
- Random-stubble strip → **lane-line strip**: calm driving is an empty dashed lane line, only incidents rise. It has a stop-line start, a P plate at the end, clock times at both ends, and the car at the head.
- Progress-bar score card, KPI grid and weighting footnote → **"Where the points went"**: one weighted bar.
- Today 3-up KPI row and the mixed-period hero → **one-story hero** (state machine) plus **painted streak days**.
- Grey maneuver icon tiles → **driver's-manual diagrams** with one-word ratings.
- Key moments and Faults as separate tables → **one examiner sheet**.
- "Awards" rings → **Badges**: a plate family with Botts'-dot tiers and one StampLanding motion.
- HUD "Drive saved" form → **Parked**, a ≤1.8 s reveal. Route naming moves to a system alert.
- Red stop disc → **neutral hold-to-end** with a −90° ring and a ratchet haptic. The green status-dot pill → the `road.lanes` symbol.
- Placeholder initial avatars → photo, or a deterministic flat fallback, plus a tier ring and a PERMIT tab.
- **New:** Driver Card (flat; portrait for Permit, landscape for License), Logbook, share card, brand mark, numbered route shields, timetable hero, "Before the score" card, demo drive, the voice system with a stored verdict line, rewritten notifications, and live Live Activity updates.
- **Type:** adds SF Pro Condensed (measured values), Compressed (plate legends only) and Rounded (collectibles only).
- **Color:** adds sign yellow, guide green, paint, marker ink, page/rule, and tokenized tier inks with light variants.
- **Motion:** DS.Motion and DS.Haptics tokens plus a one-reveal ledger. All existing at-rest motion is removed: the HomeView `tilt(0.85)` parallax, the `appeared` staggers, `loop: true` Lotties, and the DriverLicenseView holographic foil.

**Stays**
- The chassis: floating glass 3-tab bar (Today / Drives / Progress), large titles, NavigationStack push into the Report, full-screen landscape HUD, Profile & Settings sheet from the avatar, inset grouped lists, glass circular nav buttons, Week / Month / All Time segmented control, and the "Routes, days, places" search.
- The Drive Strip concept: one bucket per 20 s, height = roughness, bands at 85 / 70, markers jump footage, a draggable playhead, the same shape at every size, growing only while recording.
- Score semantics: the numeral in label color and the grade in band color. Grade table and thresholds unchanged.
- Everything v1 retired stays retired: arc gauges, Space Grotesk, SF Mono, tracked caps, gradients, glow, film grain, the holographic card, the glowing Start button.
- Blue means tappable. The 56 pt solid blue Start Drive capsule.
- The coaching sentences, and the tip → moment → footage links.
- Report order: score → coach → timeline → moments → maneuvers. Faults merge into moments, and the map becomes one small card.
- The on-device provenance line, now elevated.
- HUD glanceability: 176 pt score, elapsed and distance only, 128 pt hold control, the camera banner, and the license-aware note.
- Drives grouped by week with summaries. The full system-surface set and one App Intent. The instructor goal on Today. Progress trend with an average line.
- Layout tokens: 16 pt margins, 44 pt rows, the 4–32 spacing scale, continuous corners, no strokes or shadows on cards.

---

## 3. Tokens

### 3.1 Color

| Token | Dark | Light | Use | Contrast notes |
|---|---|---|---|---|
| `bg` | #000000 | #F2F2F7 | Screen background | — |
| `card` | #1C1C1E | #FFFFFF | Cards, inset groups | — |
| `card2` | #2C2C2E | #EFEFF4 | Odometer cells, HUD banner | — |
| `fill` | rgba(118,118,128,.24) | rgba(118,118,128,.12) | Moment tokens, hold track, lost <85-free segments | — |
| `sep` | #38383A | #C6C6C8 | Separators, chart threshold lines | — |
| `label` | #FFFFFF | #000000 | Primary text, earned ink, car | — |
| `label2` | #98989F | #6C6C70 | Units, metadata | 5.9:1 on card (dark); 5.2:1 on white, 4.7:1 on light bg |
| `label3` | #636366 | #AEAEB2 | Decoration only (empty-state car, HUD ticks). Never encodes state. | 3.5:1 on black |
| **`paint`** (new) | #7C7C80 | #86868B | Lane lines, diagram road edges, today-open dash, locked outlines, dotted future | Dark: 4.1 on card, 3.4 on card2, 5.1 on black. Light: 3.6 on white, 3.3 on bg, 3.2 on fill. Every meaningful outline is ≥3:1. |
| `tint` | #1E96FF | #0A73E5 | Tappable text and handle | 5.6 on card; 4.6 on white; 4.0 on light fill (≥15 pt semibold counts as large text) |
| `tintFill` | #0A73E5 | #0A73E5 | Filled buttons | White text 4.6:1 |
| `great` | #30D158 | #15803D | Score ≥85 | 8.4 / 5.0 |
| `okay` | #FF9F0A | #B45309 | Score 70–84 | 8.3 / 5.0 |
| `poor` | #FF453A | #9F1239 | Score <70 | 5.0 / 8.0 |
| **`markerInk`** (new) | #000000 | #FFFFFF | Digits on markers; letters on solid grade plates | On great / okay / poor: dark 10.4 / 10.2 / 6.2; light 5.0 / 5.0 / 8.0. Fixes v1's 2.6:1 failure. |
| **`signYellow`** (new) | #FFD60A | #FFCC00 | **Focus Sign only** | 12.1:1 vs dark card. Only 1.5:1 vs white, so in light mode the rim sits at the edge. |
| **`signInk`** | #111111 | #111111 | Rim and legend on yellow | 13.4 / 12.5 |
| **`guideGreen`** (new) | #0F7A5A | #005C46 | Plate fills for earned, cleared or best: Cleared plate, one-time badges, mile post, BEST/PB tabs | White legend 5.3 / 8.0. Hue 162–166° vs score green 135–142°. In light mode it sits 1.6:1 darker than `great`. |
| **`plate`** (new) | #3A3A3C | #E5E5EA | Neutral plate fill (categories, events, route shields) | Legend in `label`: 11.4 / 16.7. The rim, not the fill, carries the shape. |
| **`tierBronze`** | #CD8A57 | #9C5A2C | Tiered badge fill | Ink 6.6 / 5.4 |
| **`tierSilver`** | #C9CED6 | #6B7380 | Tiered badge fill; Driver Card rim | Ink 11.9 / 4.8 |
| **`tierGold`** | #F0B93A | #9A6B00 | Tiered badge fill | Ink 10.5 / 4.7. Darker and warmer than signYellow, and always carries studs. |
| `tierInk` | #111111 | #FFFFFF | Legends on tier fills | — |
| **`page`** / **`rule`** | #1C1C1E / #2C2C2E | #FAFAF7 / #E6E3DA | Logbook paper and ruling only | Decorative |
| `avatar1–5` | #5856D6 · #8944AB · #0E7490 · #8A6A4F · #4B5563 (both modes) | same | Fallback avatar discs, initial in white | White text 4.9–7.6 |
| `annot` | #BF5AF2 | — | Motion notes on the canvas only. Never in product. | — |

**Color rules**
1. Score colors (`great`, `okay`, `poor`) describe *how you drove*. Road inks (`signYellow`, `guideGreen`, tiers) describe *what the coach, the road or your collection is*. They never swap jobs.
2. Numerals are always `label`. The grade letter carries the band color, as a letter in rows or as a solid plate at peaks (see 4.6).
3. `tint` means tappable, and nothing else.
4. **Yellow exists on exactly one object**: the Focus Sign, plus its 8 pt tags on strip markers.
5. Guide green appears only as a plate or tab fill with a white legend. Never as text, a numeral, a bar or a chart.
6. No red plates. The octagon is never red.
7. Per viewport: at most **one** road-ink plate ≥44 pt, and at most **three** road-ink plates of any size. The Badges grid, Logbook pages and Badge Earned sheet are exempt.
8. Live surfaces (recording HUD, Dynamic Island, Live Activity, CarPlay) draw the strip in **neutral** `label2`. Band color arrives at Parked: "color is a verdict, and verdicts come when you park."
9. Grey (`label2`) is for metadata and units only. Coaching sentences, Focus bodies and fixes are set in `label`.

### 3.2 Type

All system fonts, nothing bundled. HTML mapping:
- SF Pro: `-apple-system, "SF Pro Text"/"SF Pro Display"`
- Condensed: `"SF Pro Condensed", "SF Pro Display"; font-stretch: condensed`
- Compressed: `"SF Pro Compressed"; font-stretch: extra-condensed`
- Rounded: `ui-rounded, "SF Pro Rounded"`
- Tabular figures: `font-variant-numeric: tabular-nums`

| Role | Family | Size / line height | Weight | Tracking | Figures | Where |
|---|---|---|---|---|---|---|
| Large title | SF Pro | 34/41 | Bold | system | — | Nav titles; Report custom title |
| Section header (a sentence) | SF Pro | 22/28 (Title 2) | Bold | system | — | "Where the points went", etc. |
| Voice headline | SF Pro | 20/25 (Title 3) | Semibold | system | — | Report insight sentence, leaderboard header |
| Focus title | SF Pro | 22/28 | Bold | system | — | Focus module |
| Headline / Body | SF Pro | 17/22 | Semibold / Regular | system | tabular for numbers | Rows, bodies, fixes |
| Subheadline | SF Pro | 15/20 | Regular / Semibold | system | — | Eyebrows, rating words, voice lines |
| Footnote | SF Pro | 13/18 | Regular | system | tabular | Metadata, units |
| Caption 1 | SF Pro | 12/16 | Semibold | system | — | Points-instrument names only |
| Caption 2 | SF Pro | 11/13 | Semibold | system | — | Weekday initials, chart threshold labels |
| **Hero score** (judged) | SF Pro Display | HUD 176 · Parked 132 · Report 112 · Today/Progress 88 · share 280 px | Bold | −4 · −3 · −2.5 · −2 · −6 px | tabular | Line height 0.92× |
| Row score | SF Pro | 22 | Semibold | 0 | tabular | Drives, maneuvers |
| Grade letter (text) | SF Pro | rows 15 · HUD 56 · LA 22 | Bold | 0 | — | Band color. Use "−" (U+2212). |
| **Measured** | SF Pro **Condensed** | Report clocks 28/34 · Parked clock 28 · HUD readouts 34 · LA readouts 22/17 · readouts 17 · strip-end clocks, token clocks, Drives clocks 15 · share 96 px | Semibold | 0 | tabular | Clock times, mph, g, mi, elapsed. **Only ≥15 pt.** Below 15 pt use SF Pro tabular. |
| Units | SF Pro | 0.55–0.6 × numeral | Regular | 0 | — | `label2`: "8.3" + " mi" |
| **Plate legend** | SF Pro **Compressed** | Cap height 0.42 × plate size; words 9–15 | Heavy (numerals, letters) / Bold (words) | 0 | tabular | **Uppercase allowed only here and in Driver Card field labels** |
| **Collectible** | SF Pro **Rounded** | Streak numeral 34 (widget 44) + "day streak" 17 · badge name 13 (grid) / 28 (sheet) | Bold / Semibold | 0 | tabular | **Rounded = something you collect.** Streak and badges only. Never scores or headers. |

**Dynamic Type**
- Every text role ≤34 pt maps to a text style.
- Heroes use `@ScaledMetric(relativeTo: .largeTitle)`, capped at 1.3×.
- At AX3 and above: the grade plate wraps under the numeral, the points instrument becomes 4 stacked rows, and moment tokens stack vertically.
- Screens never call `.system(size:)` directly; every font comes from the role table in `Theme.swift`.

**Scale rule (portrait app screens):** each screen has one Peak: a numeral ≥88 pt, with its solid plate. Nothing else sits between 40 and 80 pt. The HUD and system surfaces have their own scale.

### 3.3 Radii

| Item | Radius |
|---|---|
| Card (incl. Focus card, route card) | 22, continuous |
| Moment token | 14 |
| Photo / camera preview | 10 / 22 |
| Driver Card | 18 |
| Capsule buttons | height ÷ 2 |
| Grade plate | 0.28 × height |
| P plate | 3 (at 14 pt) |
| BEST / PB tab | 4 |
| Odometer cell | 4 |
| Footage instrument | 0 (full-bleed) |
| Plates | per 4.1 geometry |

### 3.4 Spacing and module rhythm

- **Scale:** 4 / 8 / 12 / 16 / 20 / 24 / 32 / 48.
- **Margins and padding:** side margin 16. Card padding 16 (Focus card 20).
- **Row heights:** list rows ≥44. Drive rows 76. Maneuver rows 64. Examiner rows ≥96.
- **Gaps:** 16 between modules without a header. A header has 32 above and 8 below. 32 after the hero band.
- **HUD insets:** leading/trailing 62, top 24, bottom 21.

**Five module shapes:**
1. **Hero band** (no card): the peak numeral, streak band, insight sentence.
2. **Card**: only for a composed object of ≥2 parts that must read together (Focus module, points instrument, latest drive, school goal, route card, trip meter).
3. **Rows**: any list of ≥2 like items, as an inset grouped list (tips, examiner sheet, maneuvers, timetable, skills, friends, drives).
4. **Shelf**: horizontal scroll of objects with identity (routes), using `.scrollTargetBehavior(.viewAligned)`.
5. **Full-bleed instrument**: used once, for the Report footage + readout + strip.

**When NOT to use a card**
- Never put a hero numeral, the streak, or an insight sentence in a card.
- Never stack like items as cards; use rows.
- Two cards may be adjacent only with a sentence header between them.
- No grey right-aligned section captions.
- At most one middle dot per line; metadata is laid out in columns.

### 3.5 Motion and haptic tokens (DS.Motion, DS.Haptics)

| Token | Spec | Reduce Motion |
|---|---|---|
| **ROLL** | Integer stepping, each step `.contentTransition(.numericText(value:))` with `.snappy(duration: 0.18)`. Step interval = span ÷ steps, clamped 55–150 ms. Max 10 steps; if \|Δ\| > 10, start at final ∓ 10. **No per-step haptic.** One haptic when it lands. No custom digit drum. | Final value, 0.2 s crossfade |
| **DRAW** | Strip fills left to right at 8 ms per bucket, clamped 300–600 ms, `timingCurve(0.25, 0.1, 0.25, 1.0)` | Strip fades in 0.2 s |
| **STAMP** | Scale 1.25 → 1.0, opacity 0 → 1 over the first 60 ms, `spring(response: 0.32, dampingFraction: 0.7)`. Rotation 0, except Logbook stamps, which rest at a deterministic −4…+6° from an id hash. `stamp` haptic at ~120 ms. No ripple ring. | 150 ms opacity; haptic kept |
| **DRIVE** | Car moves. Tap-to-jump: `spring(response: 0.5, dampingFraction: 1)`. Live advance: `.smooth(duration: 0.4)`. | Instant reposition |
| **SETTLE** | `.smooth(duration: 0.3)` for state crossfades and layout | Instant |
| **MORPH** | Focus cleared: `spring(response: 0.4, dampingFraction: 0.8)` | 200 ms crossfade |
| **PRESS** | System button styles. Standalone cards scale 0.97 with `spring(0.2, bounce 0)`. Seamed rows get a fill highlight, never scale. | Unchanged |

| Haptic | Spec |
|---|---|
| `select` | `.selection` (marker detents, tap-to-jump) |
| `land` | `.success` (Parked grade, goal events) |
| `stamp` | `.impact(.rigid, 0.8)` |
| `soft` | `.impact(.soft, 0.6)` (calm path, Driver Card reveal) |
| `start` | `.impact(.medium)` (Start Drive) |
| `light` | `.impact(.light)` (streak +1, rank move) |
| `rumbleOkay` / `rumblePoor` | Core Haptics transient, intensity / sharpness 0.35 / 0.15 and 0.6 / 0.3 |
| `curb` | `.impact(.rigid, 0.5)` (strip ends) |
| `ratchet` | 4 transients at 200 / 400 / 600 / 800 ms; intensity 0.3 / 0.45 / 0.6 / 1.0; sharpness 0.5 / 0.5 / 0.6 / 0.8 |

**Budgets**
- Zero haptics while recording, except the ratchet, which answers the driver's own touch.
- At most 2 haptics in Parked.
- Rumble transients at least 35 ms apart. Respect the system haptics setting and `CHHapticEngine` capability.

**Banned in code**, enforced by a pre-commit grep: `repeatForever`, `loop: true`, `onAppear { withAnimation`, and CMMotionManager-driven UI.

---

## 4. Signature elements

### 4.1 Plate family: the glyph grammar

**Geometry** in a box of side *s*. Polygons are drawn in SVG with rounded corners using this trick: inset the polygon by *r*, then add `stroke` in the same color, `stroke-width=2r`, `stroke-linejoin=round`.

| Shape | Geometry (s × s box) | Corner r | Legend box (24-unit grid scaled into) |
|---|---|---|---|
| OCTAGON | Points (0.29,0) (0.71,0) (1,0.29) (1,0.71) (0.71,1) (0.29,1) (0,0.71) (0,0.29), in units of s | 0.08s | 0.6s, centered |
| DIAMOND | `div` square of side 0.707s, rotate 45°, centered | 0.12s | 0.5s, centered, not rotated |
| REGULATORY | Rect 0.78s × s | 0.12s | 0.6s, centered |
| YIELD | Triangle (0,0) (s,0) (0.5s,0.88s) | 0.12s | 0.42s, centered at 38% from top |
| GUIDE | Rect, height s, width = max(1.4s, legend + 0.5s) | 0.18s | Height 0.6s |
| SHIELD | In 24 units: `M5 1H19Q23 1 23 5V10C23 16.5 18 20.5 12 23C6 20.5 1 16.5 1 10V5Q1 1 5 1Z` | built-in | 0.5s at 45% from top |
| POST | Body 0.56s × 0.80s, r 0.2s; stem 0.1s × 0.2s under, centered | 0.2s | 0.42s in body |
| SQUARE | Rounded square of side 0.82s | 0.22 × side | 0.6s |

**Rim:** inset 0.06s, stroke max(1, 0.05s), in the legend color. Plates ≤20 pt: rim 1 pt, inset 1 pt. On yellow in light mode the rim sits at the outer edge, stroke max(1.5, 0.06s).

**Legends** are solid shapes, or strokes **4 units wide** on the 24-unit legend grid with round caps and joins. Numerals and letters are Compressed Heavy.

| Legend | Construction (24-unit legend grid) |
|---|---|
| Stop line | Rect x3 y10 w18 h4 r2 |
| Up arrow | Shaft (12,21)→(12,9); head triangle (12,2) (20,11) (4,11) |
| Curve arrow (R; mirror for L) | Path `M7 21V14Q7 7 14 7`; head triangle (13,1) (22,7) (13,13) |
| Winding road | Path `M9 22C9 17 15 17 15 12C15 8 10 8 10 5` + head 8 units wide pointing up at (10,1) |
| Pace » | `M5 5L11 12L5 19` and `M13 5L19 12L13 19` |
| Two cars (tailgating) | Rects x7 y2 w10 h9 r3 and x7 y13 w10 h9 r3 |
| Lane drift | Dashed vertical line x4 (dash 4, gap 3, w3) + arrow `M10 20L18 6` with head |
| Eye (distraction) | Filled lens `M1 12Q12 2 23 12Q12 22 1 12Z`; pupil knockout r5 in plate fill; dot r2.5 |
| Check | `M4 12.5L10 18L20 6` |
| Stop Ahead (Focus braking) | Filled octagon in the 12×12 box (6,10)–(18,22) + up arrow above: shaft (12,9)→(12,5) w3, head (12,0) (16.5,5) (7.5,5) |
| Mini yield (Focus safety) | Outline triangle (3,4) (21,4) (12,20), stroke 3 |
| Wave | Three humps `M1 14Q4.5 7 8 14T15 14T22 14` |
| Crescent | Circle r9 at (12,12) minus circle r8 at (16,9) |
| Sun on horizon | Rect x2 y17 w20 h4 r2 + half-disc r7 centered at (12,17) |
| Star | 5-point, outer r10, inner r4.5, round join r1.5 |
| Laurel | Two arcs of 6 leaves (each an ellipse 4×7), set along r10 arcs from 200–340° and mirrored |
| Three discs | r3.5 at x5, 12, 19; y12 |
| Seven dashes | 7 rects w2.4 h8 r1.2, gap 0.9, centered |
| Long arrow | Shaft (2,12)→(18,12) + head (24,12) (16,5) (16,19) |
| Up chevrons ×2 / ×3 | `M5 18L12 11L19 18` repeated at 7-unit (×2) or 6.5-unit (×3) offsets |

**Styles**

| Style | Fill | Rim + legend | Used for |
|---|---|---|---|
| NEUTRAL | `plate` | `label` | Category and event plates at rest; route shields |
| INK | `label` | `bg` color | P plate, PERMIT tab |
| SIGN | `signYellow` | `signInk` | Focus Sign only |
| GUIDE | `guideGreen` | #FFFFFF | Cleared plate, earned one-time badges, mile post, BEST/PB tabs |
| TIER | tier color | `tierInk` | Tiered badges |
| LOCKED | none | 1.5 pt `paint` outline + `paint` legend | Locked badges |

**Category map.** Events inherit their category's plate.

| Tip category / event | Plate | Legend |
|---|---|---|
| Braking / Hard Brake | OCTAGON | Stop line |
| Acceleration / Hard Accel | REGULATORY | Up arrow |
| Cornering / Sharp Left, Sharp Right | DIAMOND | Curve arrow, mirrored by direction |
| Smoothness | DIAMOND | Winding road |
| Speed | DIAMOND | Pace ». **Never a number. No speed-limit data exists.** |
| Safety / Tailgating · Lane Drift · Distraction | YIELD | Two cars · lane drift · eye. A Safety tip with no linked event: rim only. |
| Positive | GUIDE (green) | Check |
| Not Scored | SQUARE, 1.5 pt dashed `paint` outline, no fill | "i" in `label2` |

The family reads as: octagon = stopping, regulatory = going, diamond = how you handled the road, yield = other road users and attention, guide = things you earned.

**Placement contract** (a design-review checklist)
1. One family, one job. A plate always encodes a category, event, route, count or award. Never decoration.
2. Respect the per-viewport cap in color rule 7.
3. Never on chrome. The tab bar, nav bar, buttons, alerts, Settings rows, sign-in and verify-email screens use SF Symbols at `.semibold`.
4. Never on the recording HUD. Only the car, neutral bars and ticks appear there.
5. Shape is always paired with text or color. VoiceOver reads the meaning ("Braking"), never the shape.
6. No red plates. No sign puns. No textures, sheen or novelty highway fonts.
7. The vocabulary is taught once, on onboarding page 1.

### 4.2 The Car (the only character)

A **side profile facing right**, built from Duolingo primitives. One flat fill, no face, no spokes.

| Size | Construction |
|---|---|
| **L 28×16** | Body rect x0 y5 w28 h7 r3.5. Cabin rect x7 y0 w14 h7 r3.5. Window knockouts (`bg` color) 4.5×3 r1 at (9.5, 1.8) and (15, 1.8). Wheels d6 centered at (7, 13) and (21, 13), each inside a 1.5 pt `bg` knockout ring. |
| **M 18×10** | Body 18×5 r2.5 at y3.5. Cabin 9×4.5 r2.25 at x4.5. One window 5×2 r0.8 at (6.5, 1.2). Wheels d4 at (4.5, 8) and (13.5, 8) with 1 pt knockouts. |
| **S 12×7** | Body 12×4 r2 at y3. Cabin 6×3.5 r1.75 at (3, 0). No wheels or windows. |
| **XL 56×32** | L scaled ×2. Empty states, Driver Card. |

**Color by context**
- `label` by default.
- `label2` on the recording HUD.
- `tint` on the Report, where it is the draggable handle.
- `label3` in empty states.
- White or black on the share card.

**Diagram car** (not the character): a top-down rect 6×10 r2 in `label`. Used only inside maneuver diagrams.

**Motion:** DRIVE only, triggered by a data commit, the user's finger, or Parked. Never idles, bobs, bounces or spins its wheels. Reduce Motion: teleport.

### 4.3 Lane-Line Strip

**Data:** bucket = 20 s. Bucket value *q* = **10th percentile** of per-second control quality in the window, so a 2 s hard brake isn't averaged away. Synced-only drives fall back to events.

**Anatomy** (width W, bar zone height H, n = ⌈duration ÷ 20 s⌉, pitch p = W ÷ n)

- **Baseline:** a continuous dashed lane line with a fixed rhythm starting at x = 0 (not per bucket), in `paint`.

  | Class | H | Thickness | Dash | Gap |
  |---|---|---|---|---|
  | L | ≥40 | 3 | 8 | 6 |
  | M | 20–39 | 2 | 6 | 4 |
  | S | <20 | 1.5 | 3 | 2 |

- **Calm** (q ≥ 85): nothing above the baseline.
- **Okay bar** (70 ≤ q < 85): height H × (0.30 + 0.25 × (85 − q) ÷ 15), color `okay`.
- **Poor bar** (q < 70): height H × (0.60 + 0.40 × min(1, (70 − q) ÷ 30)), color `poor`.
- **Bar shape:** width p − 1.5 (min 1.5). Top corners r min(1.5, w ÷ 2). Sits on the baseline.
- **Start pin:** stop-line bar, 2 pt wide × clamp(0.4H, 10, 18) tall, r1, `label`, crossing the baseline at x = 0.
- **End pin** (completed drives only): INK **P plate** 14×14 r3 (S class: 10×10 r2), "P" in Compressed Heavy at 0.72 × plate height, centered on the baseline at x = W.
- **Future** (recording): dots 1.5 pt at 4 pt pitch (S class: 1 at 3), `paint` at 60%.
- **End clocks:** 6 pt below the baseline. Start left-aligned, end right-aligned. L class: Condensed Semibold 15 `label`. M and S: SF Pro 13 tabular `label2`.
- **Markers** (completed, H ≥ 24): disc 18 pt in the bucket's band color, digit SF Pro Bold 11 in `markerInk`, centered on the bucket, 4 pt above the bar top. H < 24: 5 pt band dot, no digit. Live surfaces: HUD gets neutral `label3` ticks 2×8; Island and Live Activity get none.
- **Focus tag:** 8 pt yellow diamond (0.75 pt `signInk` rim) overlapping the top-right of each marker linked to the current job. Report and Today only.
- **Clean-stretch bracket** (Report only, run ≥3 min): 1.5 pt `paint` line 10 pt below the baseline spanning the run, with 4 pt end ticks pointing up. Label "6 min clean" in 13 `label2`, centered under it.
- **Live rendering** (HUD, Island, LA, CarPlay): bars in `label2`, no band color.

**Sizes**

| Surface | W | H | Class | Ends | Markers | Car |
|---|---|---|---|---|---|---|
| Report instrument | 370 | 72 | L | Condensed 15 | 18 pt discs + tags | L tint (handle) |
| Parked | 750 | 44 | L | Condensed 15 | 18 pt discs | L label, parks |
| Share card | 936 px | 200 px | L ×3 | omitted (clocks in hero) | 54 px | L ×3 |
| Today latest drive | 338 | 40 | L | Condensed 15 | discs + tags | none |
| HUD recording | 750 | 28 | M | start only | ticks | M label2 at head |
| Drives row | flex (~200) | 18 | S | none | 5 pt dots | none |
| Live Activity | 338 | 24 | M | none | none | M label |
| Island expanded / compact | 338 / 36 | 20 / 12 | M / S | none | none | S label |
| Widget medium | 332 | 18 | S | SF 13 | dots | none |
| Lock Screen rectangular | 150 | 14 | S | none | none | none |
| Token excerpt | 40 | 20 | S | none | none | none |

**Behavior**
- **Recording:** each commit appends one bucket (the bar grows from the baseline, `.smooth(0.3)`) and the car advances one pitch (DRIVE 0.4 s). Nothing moves between commits.
- **Report at rest:** the car sits at the **worst moment**, with footage cued 3 s before it. A drive with no moments: the car is parked just left of the P plate (front bumper 2 pt from it).
- **Scrub:** `DragGesture(minimumDistance: 12)`. The car follows the finger. A 2 pt `tint` playhead runs from the car's roof to the top of the bar zone. A bubble (24 tall, r6, `label` fill, elapsed time "4:12" in SF Pro Semibold 13 tabular, `bg` color) sits 6 pt above the playhead, **only while dragging**: fades in 0.12 s, hides 0.6 s after release.
- **Haptics while scrubbing:**
  - Within ±4 pt of a marker: `select` + magnetic snap (6 pt capture, released after 10 pt).
  - Crossing an okay bar: `rumbleOkay`. A poor bar: `rumblePoor`. Calm road: silent.
  - At either end: `curb`.
- **Tap a marker or any moment token:** DRIVE spring 0.5, footage seeks to the moment −3 s, one `select`.
- **Double-tap:** the car drives home to P.
- **VoiceOver:** adjustable element "Drive timeline". Swipe up/down jumps between moments. Value: "Moment 1 of 3, hard brake, 0.42 g, 3:32 PM."
- **Teach once:** on the first Report ever, the car nudges back one pitch and returns (0.6 s), with a TipKit popover "Drag the car back to rewatch any moment." Retired after the first drag.

### 4.4 Moment token

161×64 when two sit in a row on a 330 inner width (8 gap). r14, `fill`, padding 10.
- Row 1: marker disc 18 (band color, `markerInk` digit), 6 gap, clock "3:32 PM" in Condensed Semibold 15 **`tint`** (it is tappable). Right-aligned on the same row: a 40×20 strip excerpt (9 buckets centered on the moment, S class, incident bars in band color).
- Row 2 (y 36): "Hard brake, 0.42 g" in 13 `label2`.
- Press: scale 0.97.
- Tap: deep-links to that moment on the Report timeline, with the car there and footage cued −3 s.
- VoiceOver: "Moment 1, hard brake at 3:32 PM, 0.42 g. Double-tap to watch."

### 4.5 Focus Sign and "Your one job"

**Sign:** DIAMOND, SIGN style. Legend by category: Braking = Stop Ahead, Acceleration = up arrow, Cornering = curve arrow, Smoothness = winding road, Speed = pace », Safety = mini yield.

**Sizes**
- 8: strip tag, no legend.
- 20: rows, Lock Screen.
- 44: module, Parked verdict.
- 64: HUD Ready.
- 120: onboarding.

**Monochrome version** (Lock Screen Live Activity, accessory widget): 1.5 pt outline + legend in `label2` or vibrant, no fill.

**Module** (card, padding 20, inner width 330)
1. HStack (gap 12): sign 44 | VStack (gap 2): eyebrow **"Your one job next drive"** (15 Semibold `label`), then the title (22/28 Bold `label`, ≤2 lines).
2. +8: body in 17/22 Regular **`label`**, ≤3 lines.
3. +16: up to 2 moment tokens.
4. +12 (Today only): "Set by Friday's School run" in 13 `label2`.

On Today, the Start Drive capsule sits 16 pt directly under this card, so starting a drive is literally "go do this job".

**Lifecycle**
- **SET.** When a valid drive (≥2 min) saves with no active job, its first actionable tip becomes the job. Positive and Not Scored tips never become the job. The job stores: category, linked event types, baseline count (linked events in that drive), title, `shortTitle` (≤5 words, for the HUD), body and moment IDs.
- **CARRIED.** Today module. HUD Ready, before Start only; it crossfades out in 200 ms when recording starts. Lock Screen LA (20 pt monochrome, static). Accessory circular widget. **Never** on the recording HUD or in the Dynamic Island.
- **CHECKED** on the next valid drive. Drives under 2 min get no check.
  - *Not tested:* none of the category's test situations occurred. Braking and Acceleration: no Stop maneuver. Cornering: no turn or roundabout. Smoothness and Speed: under 5 min moving. Safety: camera saw the road <50% of the drive.
  - *Cleared:* tested, 0 linked events, and the category sub-score ≥85. Speed and Safety have no sub-score, so 0 events is enough.
  - *Better:* tested, and linked events < baseline.
  - *Still:* anything else.
- **RETIRED.** A second consecutive Cleared closes the job. It adds to "Jobs cleared" in the Logbook, and the next job is SET from this drive. If this drive has no actionable tip, the guide plate reads "Nothing to fix this time."
- **Re-set.** After 4 checks with no Cleared, if the latest drive's first actionable tip is in a different category, the job is replaced quietly: "New job: …".

**Visuals**
- **Only at Parked:** Cleared and Retired MORPH the diamond. It counter-rotates 45° → 0°, becoming a SQUARE plate (0.82s, r 0.22 × side) in guide green with a white check (400 ms). Better, Still and Not tested: the diamond stays still.
- **Everywhere else**, verdicts are a single text line. Cleared or Retired uses SF `checkmark.circle.fill` in `great` + 15 Semibold `label`. Others are text only. Never red.

### 4.6 Grade plate

**Solid, at peaks only, at most one per screen:** Today and Progress heroes (h 40), Report hero (h 56), Parked (h 64), share card (h 168 px).

**Geometry**
- Min width h, horizontal padding 0.22h, r 0.28h. Fill = band color.
- Letter: SF Pro Bold 0.6h in `markerInk`. "+" and "−" at 0.75× letter size, raised 0.1 em.
- Sits right of the numeral with a gap of 0.08 × numeral size, bottom-aligned to the numeral baseline.

**Everywhere else:** the v1 rule. Numeral in `label`, letter in band color. Never a tinted pill.

**Live surfaces:** a plain letter whose band changes only after the new band holds for **2 committed buckets (40 s)**.

**Reveal:** STAMP, plus the `land` haptic at Parked.

### 4.7 Timetable hero (departure → arrival)

- Clocks: "3:28 PM" left and "3:52 PM" right, in Condensed Semibold 28 `label`, with "PM" in 17 Regular `label2`.
- Between them: an M-class dashed lane line (y-centered on the clocks) ending in the P plate 14.
- Centered above the line: "24 min   8.3 mi" (numerals 15 Semibold `label`, units 13 `label2`).
- **Timetable rows** (Report): label left (17 Regular), value right (Condensed Semibold 17 `label`), optional "(was X)" against the named route's average in 15 `label2`. The delta turns `okay` only when ≥15% worse.

### 4.8 "Where the points went"

Card, inner width 338. One bar 338×28.
- Four segments with widths (338 − 9) × [0.30, 0.25, 0.25, 0.20] = **98.7 / 82.3 / 82.3 / 65.8**, 3 pt gaps. Outer corners r8, inner r3.
- In each segment, the **earned** fraction (sub-score ÷ 100) fills from the left in `label`. The **lost** remainder is band color when the sub-score is <85, otherwise `fill`.
- Under each segment, left-aligned to it, 8 below:
  1. NEUTRAL category plate 20 + 6 gap + score (SF Pro Semibold 20 `label`).
  2. Name in Caption 1 12 Semibold `label2`.
  3. Points lost "−4.8" in 13 Semibold: band color if <85, else `label2`.
- Caption, 16 below: one voice sentence in 15 Regular `label`.
- Points lost = weight × (100 − sub). The total ink length equals the overall score, which is exactly the weighted sum.
- First reveal only: earned fills sweep left to right, 500 ms total, 80 ms stagger.

### 4.9 Driver's-manual maneuver diagrams

40×40, drawn **directly on the card** (no tile), ≤5 strokes.
- Road edges: 1.5 `paint`. Center dashes: 1.5 `paint`, 4/3. Stop line: 2.5 `label`.
- Diagram car: 6×10 r2 `label`, facing up.
- Path: 2.5 pt, round caps, 5 pt arrowhead. Color `label` at ≥85, `okay` 70–84, `poor` <70.

| Type | Geometry (40-unit box) |
|---|---|
| Straight | Edges x10, x30; dashes x20; car at (17,24); path (20,22)→(20,4) ↑ |
| Stop | Edges x10, x30; stop line y12 from x10 to x30; car at (17,20); path (20,30)→(20,14), flat cap, no arrowhead |
| Left turn | Cross street y8–20 (edges); approach road x14–26 from y20 to y40; car at (17,28); path (20,28)→(20,16), curving to (4,14) ← |
| Right turn | Mirror of left turn |
| Roundabout | Island circle d14 at (20,18), 1.5 `paint`; approach edges x16, x24 from y30 to y40; path enters at the bottom, circulates counterclockwise 270° on r11, exits ← at (6,18) |
| Lane change | Edges x8, x32; dashed divider x20; car at (11,26); S-path (14,26)→(26,6) ↑ |
| Parking | Lane edge x8; three-sided bay 14×18 at (22,4), open toward the lane; path from car (9,28) curving into the bay |

Left-hand-traffic regions (GB, IE, AU, NZ, JP, IN, ZA, SG, HK, MY, TH, ID) mirror every diagram, and the roundabout runs clockwise.

**Row** (64 min)
- Diagram 40 | 12 gap.
- Line 1: "Stops" 17 Semibold `label` + " ×9" 17 Regular `label2`.
- Line 2: rating word 15 Semibold (band color if <85, else `label`) + "  0.42 g peak, 27 → 0 mph" 15 Regular `label2` tabular.
- Trailing: score 22 Semibold + grade 15 Bold.
- Tap pushes the instance list: one row per maneuver with its own diagram, clock time, entry → exit, peak g and a moment token.

**Rating words** (≥85 / 70–84 / <70)

| Maneuver | Words |
|---|---|
| Stop | Smooth / Firm / Harsh |
| Turns | Clean / Quick / Sharp |
| Roundabout | Clean / Quick / Rushed |
| Lane change | Clean / Quick / Abrupt |
| Straight | Steady / Uneven / Jerky |
| Parking | Gentle / Firm / Rough |

### 4.10 Examiner sheet, and "Before the score"

**Row** (inset grouped, ≥96, padding 12/16)
- Marker disc 18 at leading.
- Column at x 44:
  - Line 1: clock in Condensed Semibold 15 `label` + 8 + NEUTRAL event plate 20 + 6 + "Hard brake, 0.42 g" 15 `label2`.
  - Line 2: fault title 17 Semibold `label`, with trailing tally glyph + severity word 15 Semibold.
  - Line 3: the fix in 15 Regular `label`, ≤2 lines.
- Tally glyph, 14×12: Minor = one 2×12 bar in `label2`. Serious = two bars in `okay`. Dangerous = two bars + a diagonal, in `poor`.
- Tapping a row scrolls up to the instrument and drives the car to the moment.
- Last row: "Show all 7 events" in `tint`.

**"Before the score"** (only when a fault is Dangerous). It is the first module under the title and cannot be dismissed. Card:
- NEUTRAL category plate 44 (never yellow).
- "Before the score" 20 Semibold `label`.
- Body 17 `label`: the plain fact, then why it matters, with no score talk and no wink.
- One moment token.
- "Watch it" `tint` text button.
- Red appears only on the marker and the g value.
- Drawn as a 402×300 variant frame on the Report board.

### 4.11 Route shields and BEST / PB tabs

- **Shield:** NEUTRAL style. Route number in Compressed Heavy. Sizes: 16 (widgets, Logbook), 20 (rows, Today), 24 (Parked), 28 (Report, route cards), 96 px (share). Always followed by the user's route name.
- **Numbering:** numbers are assigned in naming order and never reused or renumbered.
- **Unnamed drives:** no shield. The name is the weekday + part of day: "Tuesday evening". Parts of day: morning <12, afternoon 12–17, evening 17–21, night ≥21.
- **BEST tab:** GUIDE fill, height 16 (rows) / 20 (Report, Parked), r4, padding 5, "BEST" in Compressed Bold 10/12, white. Shown when the drive is the top score on a route with ≥3 drives; stored at save. Placed 4 pt right of the route name.
- **PB tab:** the all-time personal best. Same spec, placed beside the grade plate on Report and Parked, and beside the name in rows. It takes precedence over BEST.
- **Route card** (Progress shelf, 160×140, r22, padding 12):
  - Shield 20 + name 15 Semibold.
  - GPS silhouette 136×48: the latest drive's polyline, Douglas-Peucker simplified to ≤40 points, aspect-fit, 2 pt `label` stroke, stop-line start bar 2×10, P plate 10.
  - Stats: "82" 22 Semibold + " avg" 13 `label2`, and "91" + " best".
  - "Improving" in 13 Semibold `great` + SF `arrow.up.right`, only when true.
- Silhouettes never appear on share images.

### 4.12 Painted streak days and the mile post

**Hero band** (no card)
- Row 1: "5" in Rounded Bold 34 `label` + " day streak" in Rounded Semibold 17 `label`.
- Row 2 (+8): **7 dashes** for the rolling last 7 days ending today. Each is a 28×6 capsule, 8 gap, 244 wide.
  - Driven: solid `label`.
  - Today, not yet driven: 1.5 pt dashed `paint` outline (dash 3, gap 2).
  - Missed: nothing (the lane line breaks).
- Weekday initials in Caption 2 `label2`, 4 below.
- Row 3 (+8): one voice line in 15 Regular `label`.

**Milestone days** (7, 30, 100), that day only: Row 2 becomes a GUIDE **POST**, 28×44, white rim. "DAYS" in Compressed Bold 8 sits above "7" in Compressed Heavy 22. Line: "7 days in a row. That's a mile marker."

**Motion:** once per calendar day (`lastStreakAnimatedDay`), on the first Today appearance after the first valid drive of the day: today's dash fills left to right in 350 ms, the numeral ROLLs +1, `light` haptic.

**Reminders:** License drivers get one at 6:00 PM (default on, only if the streak is ≥2 and there's no drive yet today). **Permit holders: off by default.** Never 8 PM – 7 AM, never while recording, at most one per day. No loss language.

### 4.13 Badges

Named **Badges** everywhere.

**Tiered badges.** The fill is the tier color, with 1 / 2 / 3 **Botts' dots** (0.1s discs in legend color, 0.16s apart, along the bottom inside edge). Locked = LOCKED style.

| Badge | Container | Legend | B / S / G | Sample state |
|---|---|---|---|---|
| Road Warrior | POST | Tier threshold numeral (5 / 25 / 100) over "DRIVES" | 5 / 25 / 100 drives | Silver; 28 of 100 to Gold |
| Consistent Driver | REGULATORY | "80+" | 5 / 25 / 50 drives at 80+ | Bronze; 19 of 25 |
| Smooth Operator | GUIDE | Wave | 3 / 10 / 25 drives over 90 | Bronze; 7 of 10 |
| Marathon Driver | GUIDE | Threshold in 4 odometer cells over "MIN" | 60 / 300 / 1000 min | Silver; 728 of 1,000 min |
| Perfectionist | REGULATORY | "95+" | 1 / 5 / 15 drives at 95+ | Bronze; 1 of 5 |

**One-time badges.** GUIDE fill when earned, LOCKED otherwise.

| Badge | Container | Legend | Sample |
|---|---|---|---|
| Safe Start | GUIDE | Car M | Earned |
| Night Owl | GUIDE | Crescent | — |
| Early Bird | GUIDE | Sun on horizon | Earned |
| Weekend Warrior | REGULATORY | "SAT" over "SUN" | — |
| Long Haul | POST | Long arrow | — |
| Perfect Run | REGULATORY | Check | — |
| Hot Streak | POST | Up chevrons ×3 | — |
| Score Rocket | REGULATORY | Up chevrons ×2 | — |
| 7-Day Streak | POST | "7" over "DAYS" | — |
| Hat Trick | GUIDE | Three discs | — |
| Clean Week | GUIDE | Seven dashes | — |
| Route Ace | SHIELD | Star | — |
| Route Regular | SHIELD | Laurel (only inside this badge) | Earned |

Sample total: **8 of 18**. No diamonds and no yellow among badges.

- **Sizes:** grid 72, Progress preview 64, sheet 120, friend rows 16, Logbook stamp 44.
- **Progress toward the next tier or unlock:** counts ≤10 show as a row of Botts' dots (filled `label`, hollow 1.5 pt `paint`). Larger counts show "19 of 25" in 13 `label2`.
- **Grid labels:** name in Rounded Semibold 13 `label`; tier word or earn date in 13 `label2`.
- **StampLanding** (STAMP token) plays on unlock, once per reward. It replaces the badgeUnlock, tierUp, personalBest and rankUp Lotties.
- **Tier-up:** the next dot STAMPs and the fill crossfades in 300 ms.

**Badge Earned sheet** (`.medium` detent; system glass close button)
- 120 pt plate STAMPs 32 pt from the top.
- Name in Rounded Bold 28 `label`.
- Why-line in 17 `label2`.
- "Next: Gold at 25" in 15 `label2`.
- Optional row: 40 pt icon preview + "Unlocks the Smooth app icon" + `tint` "Use icon".
- Buttons: Share (bordered) and Done (prominent `tintFill`).
- Shown the first time the app is foregrounded after Parked is dismissed. Never over the HUD, never while moving. Multiple badges page with page dots.

### 4.14 Papers: Driver Card and Logbook

**Driver Card** (flat; no tilt, holo or sheen)
- **Permit: portrait 240×380. License: landscape 358×226.** r18. Face `card`. 2 pt inset rim in the tier color (inset 6).
- **Header band:** 44 pt inside the rim, INK fill, top corners r12. Brand mark 20 + "Drive" 17 Bold in `bg` color on the left; "LEARNER" or "DRIVER" in Compressed Bold 15 `bg` on the right.
- **Field labels:** Compressed Semibold 10 `label2`, uppercase (allowed inside the card). **Values:** SF Pro Semibold 20 tabular `label`; the card number in Condensed Semibold 15.
- **Photo** 72×90 r10. Fallback: car L in `bg` color on an INK rect.
- **Car** L 56×32 in `label` at bottom-left; tier Botts' dots (6 pt, tier color) at bottom-right.
- **Hold to reveal** (≥0.5 s): fades in a second ink layer over 200 ms with a `soft` haptic. The layer is the most-driven route's polyline (2 pt tier color at 40%) plus repeating 6 pt `paint` microtext of the card number at 30%. Fades out over 200 ms on release.
- **Graduation** (license type Permit → License, confirmed by a system alert): a GUIDE "LICENSED" plate (120×44, white Compressed Heavy 22, rested at −6°) STAMPs onto the Permit card, then a 300 ms crossfade to the landscape License card. No rotation morph. Permit Logbook pages close as "Volume 1: Permit". Reversible within 7 days.

**Logbook** (pushed from Progress)
- One page per week (`TabView(.page)`). `page` fill, 44 pt rows ruled with 0.5 pt `rule` lines, a 1 pt `rule` margin line at x 56.
- Columns:
  - Margin: "Fri 16" 15 Semibold over "3:28 PM" 13 `label2`.
  - Shield 16 + route 15.
  - "24" 17 tabular + " min" 13 `label2`.
  - Day/night: SF `sun.max.fill` or `moon.fill`, 14 `label2`. Night = start after local civil dusk.
  - "91" 17 Semibold + grade.
- Header "Week of Oct 12" 22 Bold. Footer "5 drives, 1 h 58 m".
- **Stamps:** 44 pt single-ink 1.5 pt outlines of badge silhouettes (tier or green ink), at their deterministic angle, overlapping the right margin of the row that earned them. They land once, the first time the page is opened.
- **Endpaper:**
  - Lifetime miles in **odometer cells**: 18×26, r4, `card2`, 1 pt gaps, Condensed Semibold 20 tabular. The tenths cell is inverted (`label` fill, `bg` digit).
  - Named stats: Hours behind the wheel · Night hours · Longest clean stretch · Softest stop · Most driven (shield) · You drive best (time of day) · Jobs cleared.
- Footnote: "Not an official state log. Keep your state's form too."

### 4.15 Brand mark, avatars, PERMIT tab

- **Brand mark** (24 grid): baseline y17. Dashes 6×2.5 r1.25 at x1, 9, 17. A bar 3×11 r1.5 rising from the middle dash (x10.5, y6–17). `label` on `bg`.
  - App icon: white on #000, with system dark and tinted variants.
  - Alternate icons (unlocked by badges, named in Settings > App Icon): "Night Owl", "Gold Road", "Clean Week".
  - The Live Activity glyph is the car, not the mark.
- **Avatar:** profile or Game Center photo. Fallback: a disc in `avatar1–5` (hash of uid) with a white initial in SF Pro Semibold. Today and the You row add a 2 pt tier-color ring at 2 pt offset.
- **PERMIT tab** (learners only): INK, 38×16, r4, "PERMIT" in Compressed Bold 10. Hangs centered under the avatar, overlapping it by 6. On HUD Ready it is 46×18 / 11 pt.

### 4.16 The one-reveal ledger

Every drive is revealed exactly once, at the first place it is seen:
1. Parked.
2. Otherwise, the first Report open: hero ROLL from average + plate STAMP + points sweep, and the strip DRAWs when the instrument enters the viewport.
3. Otherwise, the first time its Drives row appears: the mini strip DRAWs in 300 ms.

Revealed IDs are stored per user (local + Firestore user doc) and **cleared on auth change**. After the reveal, every view of that drive renders at rest.

---

## 5. Copy voice

**Rules**
1. Order: human subject → exact number → delta → "(was N)" → at most one context fact. Like "Mom landed 6:32am (22m early)".
2. Every compliment carries a number. Praise the behavior, never the person.
3. Corrections use instructor verbs: lift, roll, ease, brake before, look ahead. Never "bad", "poor", "fail" or "aggressive".
4. No exclamation marks, no emoji. At most one wink per screen, and never on a fault.
5. At most one middle dot per line. Metadata is layout, not strings.
6. Real events use clock time ("3:32 PM"). Elapsed time appears only in the scrub bubble and the HUD.
7. Deltas under 3 points are never mentioned.
8. Permit voice names the supervisor. Copy never urges a drive. Breaks look forward.
9. At most 14 words per sentence on Today, HUD, widgets and Live Activity.
10. Section headers are sentences in the coach's voice, in sentence case. Never schema nouns.
11. No street names (there is no geocoder). No speed-limit language (there is no limit data).
12. The **verdict line** is computed once at save and stored on the session (`verdictText`, `verdictKind`). First match wins:
    - Dangerous fault
    - All-time personal best
    - Named-route best (≥3 drives)
    - Job retired or cleared
    - First-ever conditions
    - ≥3 above the 30-day average
    - ≥3 below it
    - On average

    Each kind has 3 phrasings, rotated so none repeats within 5 drives. Templates are unit-tested against fixture drives.

**Sample lines** (canonical data)
1. Parked: **"Parked 3:52 PM"** / **"Best School run yet. (was 86)"**
2. Report hero: **"+3 vs your 88 average"**
3. Points caption: **"Braking cost 4.8 points. Everything else cost 4.7."**
4. Focus (Today): **"Your one job next drive"** / **"Start slowing earlier for stops"** / "Twice yesterday you braked harder than 0.3 g coming into a stop. Lift off about 100 ft sooner and let the car roll."
5. HUD Ready: **"Today's job"** / **"Brake earlier for stops"**
6. Retired: **"Job retired. Two drives with 0 hard starts (was 3)."**
7. Better: **"Better. 1 hard stop (was 2). Same job next drive."**
8. Still: **"Still your job. One stop came in at 0.38 g. Start slowing at the crosswalk."**
9. Not tested: **"No stops this drive, so the job carries over."**
10. Insight: **"Acceleration is up 6% across your last five drives. Braking is still where the points go."**
11. Maneuvers header and row: **"Stops cost the most"** / "Firm   0.42 g peak, 27 → 0 mph"
12. Positive tip: **"Nice: steady at speed. You held 35 mph for six minutes."**
13. Streak (Permit): **"Any 2-minute drive with your supervisor makes it 6."**
14. Leaderboard: **"You're #3 of 5 this week, up one place."**
15. Badge: **"Smooth Operator, Silver"** / "Your 10th drive over 90. Gold at 25."
16. Parked notification: title "Parked 3:52 PM · School run" / body "91 A. Best School run yet (was 86). One stop worth a look at 3:32 PM."
17. Speed gate: **"Saved. We'll show you how it went once you're parked."**

**Notification rewrites**

| Notification | Title | Body |
|---|---|---|
| Streak (License, 6 PM) | "5 days and counting" | "Any 2-minute drive today makes it 6. Not a driving day? That's fine." |
| Badge | "New badge: Smooth Operator" | "Your 10th drive over 90. It's in your Logbook." |
| Weekly recap (Sun 7 PM) | "Your week: 87 (was 83)" | "5 drives, 1 h 58 m. Best was Thursday's 93." |

These replace "Keep your N-day streak alive! 🔥" and "Badge Unlocked!".

---

## 6. Per-screen spec

### 6.0 Canonical sample state (use these exact values everywhere)

**Now and profile**
- Now: **Sat Oct 17, 10:05 AM.** That is the time on Today, Drives, Progress, Driver Card and widgets.
- Jason. **Permit.** 2019 Honda Civic. Member since Jun 4, 2026. Card DRV-260604-028. Tier **Silver**. Avatar fallback `avatar1` (indigo) "J".
- 28 drives · 12 h 8 m (728 min) · 214.6 mi · best 97 · 30-day 88 A− (up 5% this week) · streak 5 (Mon–Fri) · best streak 12 · night 1 h 40 m · softest stop 0.14 g · best time afternoons (avg 90) · jobs cleared 6.

**The drive: Fri Oct 16, School run (Route 1)**
- 3:28 PM → 3:52 PM. 24 min (moving 21, stopped 3; route average stopped 4). 8.3 mi. Avg 21 mph, top 47 mph.
- **91 A**, +3 vs 88. Route best (was 86, Fri Oct 9).
- 7 events. 28,800 motion samples, 412 GPS points, camera saw the road 96%.
- Sub-scores: braking 84 (−4.8), acceleration 96 (−1.0), cornering 90 (−2.5), smoothness 94 (−1.2).

**Strip** (73 buckets; every bucket not listed is calm)

| Bucket | q | Band | Height | Moment |
|---|---|---|---|---|
| 12 | 52 | poor | 0.84H | Moment 1 |
| 13 | 78 | okay | 0.42H | — |
| 21 | 81 | okay | 0.37H | — |
| 34 | 74 | okay | 0.48H | Moment 2 |
| 53 | 77 | okay | 0.43H | Moment 3 |
| 60 | 82 | okay | 0.35H | — |
| 61 | 80 | okay | 0.38H | — |

Longest clean stretch: buckets 35–52 = **"6 min clean"**.

**Moments and faults**

| # | Event | Clock (elapsed) | Marker | Fault | Fix |
|---|---|---|---|---|---|
| 1 | Hard brake, 0.42 g | **3:32 PM** (4:12) | red | Serious, "Braking into the stop" | "Start slowing at the crosswalk, not the stop line." |
| 2 | Sharp left, 0.36 g | **3:39 PM** (11:30) | orange | Minor, "Turning too quickly" | "Brake before the turn, not in it." |
| 3 | Hard brake, 0.33 g | **3:45 PM** (17:48) | orange | Minor, "Braking into the stop" | "Same stop as before. Start slowing at the crosswalk." |

**Maneuvers**

| Maneuver | Avg | Rating | Detail |
|---|---|---|---|
| Stops ×9 | 82 B+ | Firm | 0.42 g peak, 27 → 0 mph |
| Left turns ×6 | 86 A− | Clean | 0.36 g peak, 18 → 15 mph |
| Right turns ×5 | 93 A | Clean | 0.24 g peak, 14 → 12 mph |
| Straights ×14 | 97 A+ | Steady | 47 mph top |

**Focus**
- New job: Braking, "Start slowing earlier for stops" (short title "Brake earlier for stops"). Moments 1 and 3. Baseline 2.
- Retired job: Acceleration, "Ease onto the gas from a stop". Baseline 3 (Wed); Thu 0, Fri 0.
- Other tips: Cornering "Brake before the turn, not in it" (moment 2); Positive "Nice: steady at speed".

**This week's drives**

| Day | Start | Duration | Route | Score |
|---|---|---|---|---|
| Mon | 3:31 PM | 23 min | School run | 84 B+ |
| Tue | 5:12 PM | 18 min | Tuesday evening | 89 A− |
| Wed | 3:30 PM | 22 min | School run | 78 B |
| Thu | 4:10 PM | 31 min | Practice loop (2) | 93 A |
| Fri | 3:28 PM | 24 min | School run | 91 A, BEST |

5 drives, avg 87. Last week: 6 drives, avg 83.

**Skills vs last week:** Braking 83 (was 81) · Acceleration 94 (was 89) · Cornering 89 (was 90) · Smoothness 93 (was 93).

**Friends (this week)**

| Rank | Name | Score | Avatar | Change |
|---|---|---|---|---|
| 1 | Maya | 94 A | avatar3 | — |
| 2 | jblake | 91 A | avatar2 | — |
| 3 | You | 87 A− | avatar1 | ▲1 |
| 4 | Liam Park | 85 A− | avatar4 | ▼1 |
| 5 | Sofia R. | 82 B+ | avatar5 | — |

**Routes:** 1 School run (9 drives, avg 82, best 91, improving) · 2 Practice loop (6 drives, avg 89, best 94).

**School goal:** Coastline Driving School, "Three drives scoring 80+ this week", note **"Roll the last 10 feet into every stop."** No count is drawn (the schema has no target).

**HUD recording sample:** 12:48 elapsed, **89 A−**, 4.2 mi, 39 buckets filled.

### 6.1 Today (402 × 1420, full scroll)

**Peak:** "88" + the A− plate.

| y | Module | Spec and copy |
|---|---|---|
| 0–54 | Status bar | — |
| 54–160 | Nav | Large title **"Today"**; `navigationSubtitle` **"Saturday, October 17"** (15 `label2`). Trailing avatar 40 (indigo "J", silver ring, PERMIT tab). |
| 176 | Hero band | **"88"** 88 Bold + grade plate h40 **"A−"** (`great`). +8: **"Your 30-day score, up 5% this week. Braking is still where the points go."** 17 Semibold `label`, 2 lines. |
| 340 | Retired line | SF `checkmark.circle.fill` 17 `great` + **"Last job retired: easing onto the gas."** 15 Semibold `label` |
| 376–678 | Focus module | Sign 44 (Stop Ahead), "Your one job next drive", "Start slowing earlier for stops", body (sample line 4), tokens: ① "3:32 PM" / "Hard brake, 0.42 g" and ③ "3:45 PM" / "Hard brake, 0.33 g", then "Set by Friday's School run" |
| 694–750 | Start Drive | 370×56 `tintFill` capsule, SF `steeringwheel` 20 + **"Start Drive"** 17 Semibold white, `start` haptic |
| 782 | Streak band | "5 day streak"; dashes S M T W T F S with Sun empty, Mon–Fri solid, Sat dashed; **"Any 2-minute drive with your supervisor makes it 6."** |
| 912 | Header | **"Yesterday"** |
| 948–1107 | Latest drive card | Row 1: shield 20 "1" + **"School run"** 17 Semibold + BEST tab; trailing "91" 22 Semibold + "A". +12: strip H40 (markers 1–3, tags on 1 and 3, start pin, P plate). Row 3: "3:28 PM" left, "3:52 PM" right (Condensed 15 `label`), with "24 min   8.3 mi" centered. Tap pushes the Report. |
| 1139 | Header | **"From your instructor"** |
| 1175–1311 | Goal card | **"Three drives scoring 80+ this week"** 17 Semibold. +8: 3 pt `paint` rule (r1.5) + 12 indent + **"“Roll the last 10 feet into every stop.”"** 17 Regular `label`. +8: **"Coastline Driving School"** 13 `label2`. |
| 790–874 overlay | Tab bar | Floating glass: Today (`steeringwheel`), Drives (`road.lanes`), Progress (`chart.line.uptrend.xyaxis`), all `.semibold` |

**Hero state machine.** A SETTLE crossfade runs only when the state changes on appear; never on a timer. Reduce Motion: instant.

| State | When | Hero shows |
|---|---|---|
| A | A valid drive ended <60 min ago | Shield + name + "Parked 3:52 PM", strip H40, "91" 88 + plate, verdict line |
| B | Streak ≥2, no drive yet today, after 3 PM | The streak band, promoted to the hero position |
| C | A badge is one valid drive away | LOCKED plate 64 + "One drive to Hot Streak." |
| D | Default | 30-day score (the sample) |

**First run:**
- Car XL in `label3` on a 120 pt M-class lane line.
- **"Your first drive will show up here."** 20 Semibold.
- "Mount the phone in landscape, camera on the road. We stay quiet until you park." 15 `label2`.
- Start Drive.
- `tint` **"Watch a 20-second demo drive"**.

### 6.2 Drive Report (402 × 3320, full scroll)

**Peak:** "91" + the A plate.

**Nav:** glass back circle; trailing glass share (`square.and.arrow.up`, the **only** share entry, which opens the share sheet with the card preview) + more (`ellipsis`). The inline title "School run" appears on scroll.

| y | Module | Spec and copy |
|---|---|---|
| 106 | Title band | Shield 28 "1" + **"School run"** 34 Bold + BEST tab 20. +4: **"Friday, October 16"** 15 `label2`. |
| 184 | Timetable hero | 4.7: "3:28 PM ——— P 3:52 PM", "24 min   8.3 mi" above the line |
| 248 | Score | **"91"** 112 Bold + plate h56 **"A"**. +8: **"+3 vs your 88 average"** 17 Semibold `label`. +8: **"Best School run yet."** 22 Semibold `label` + **" (was 86)"** 22 Regular `label2`. |
| 456 | Header | **"Where the points went"** |
| 492–658 | Instrument card | 4.8. Braking 84 / −4.8 (`okay`), Acceleration 96 / −1.0, Cornering 90 / −2.5, Smoothness 94 / −1.2. Caption: sample line 3. |
| 690 | Insight band | **"Acceleration is up 6% across your last five drives. Braking is still where the points go."** 20 Semibold `label` |
| 752 | Retired line | ✓ **"Job retired. Two drives with 0 hard starts (was 3)."** |
| 788–1050 | Focus module | Same as Today, without the footnote. Body: "Twice you braked harder than 0.3 g coming into a stop. Lift off about 100 ft sooner and let the car roll." |
| 1066–1170 | Tip rows | Row 1, 52: NEUTRAL diamond (curve-left) 24 + **"Brake before the turn, not in it"** 17 Semibold + `chevron.right` 13 `label3`; expands with SETTLE to body + token ②. Row 2, 64: GUIDE check plate 24 + **"Nice: steady at speed"** 17 Semibold over "You held 35 mph for six minutes." 15 `label` |
| 1202 | Header | **"What happened"** |
| 1240–1670 | Full-bleed instrument | **Footage** 402×226, AVKit controls, poster = moment 1. **Readout bar** 402×48 on `card`: marker ① + NEUTRAL octagon 20 + **"Hard brake"** 15 Semibold; trailing **"18"** + " mph" and **"0.42"** + " g" (Condensed Semibold 17 `label`, units 13 `label2`). Away from a moment it shows the playhead clock "3:31 PM" in Condensed 15. **Strip block** 402×156 on `card`, 16 margins: W370 H72, markers + tags, bracket "6 min clean", ends "3:28 PM" / "3:52 PM", car L tint at marker 1 (rest). |
| 1702 | Header | **"How an examiner would mark it"** |
| 1740–2120 | Examiner rows | The three canonical rows (4.10) + "Show all 7 events" |
| 2152 | Header | **"Stops cost the most"** |
| 2190–2446 | Maneuver rows | 4 rows, weakest first (canonical) |
| 2478 | Header | **"Timetable"** |
| 2516–2824 | Rows | Departed **3:28 PM** · Parked **3:52 PM** · Moving **21 min** · Stopped **3 min** (was 4) · Distance **8.3 mi** · Avg speed **21 mph** · Top speed **47 mph** |
| 2856 | Header | **"The route"** |
| 2894–3054 | Route card | Silhouette 338×112 + row "Open map" `tint` with chevron |
| 3086–3240 | Trip meter card | Title **"Witnessed by this iPhone"** 17 Semibold. **"Measured on this iPhone: 28,800 motion samples at 20 Hz and 412 GPS points. The camera saw the road 96% of the drive."** 15 `label`. +12: **"Longest clean stretch: 6 min"** 15 Semibold `label` |

No bottom share capsule. No "Each bar is 20 seconds" or "Drag along the strip" captions.

### 6.3 Drives (402 × 874)

**Peak:** the first row, a left clock column plus a strip with one red dot.

- Large title **"Drives"**. Stock search field **"Routes, days, places"**; route shields appear as search tokens.
- **Section header:** **"This week"** 20 Semibold `label`. Trailing **"5 drives, avg 87"**: numerals in `label`, words in 15 `label2`.
- **Row** (76):
  - Left column 60: "Fri" 13 Semibold `label2` / "3:28 PM" Condensed Semibold 15 `label` / "24 min" 13 `label2`.
  - Middle: shield 20 + name 17 Semibold + tab. +8: strip H18 (S class, 5 pt dots, start pin, P plate 10).
  - Trailing: score 22 Semibold + grade 15 Bold.
- **Rows** (this week, newest first): Fri School run BEST 91 A · Thu Practice loop 93 A · Wed School run 78 B (strip: 2 poor bars) · Tue "Tuesday evening" (no shield) 89 A− · Mon School run 84 B+.
- **"Last week"**, **"6 drives, avg 83"**: Sat 9:40 AM, 27 min, Practice loop, 88 A− · Fri 3:29 PM, 22 min, School run, 86 A− · …
- Swipe actions and context menus are stock. No mile-post dividers.
- **Empty state:** car XL on a lane line + **"Your first drive shows up here as a strip. A clean drive looks like an empty road."**

### 6.4 Progress (402 × 1900, full scroll)

**Peak:** "87" + the A− plate.

| y | Module | Spec and copy |
|---|---|---|
| 54–150 | Nav | Large title **"Progress"** |
| 160 | Segmented control | **Week** / Month / All Time (stock) |
| 216 | Hero band | **"87"** 88 Bold + plate h40 **"A−"**. +8: **"This week's average, up 5% (was 83)."** 17 Semibold |
| 358–578 | Trend card | Swift Charts, Mon–Sun. Bars 28 wide, top r4: 84 `okay`, 89 `paint`, 78 `okay`, 93 `paint`, 91 `paint`, Sat and Sun empty. Y 60–100. Average line 87: 1 pt `label2`, dash 4/3. Thresholds 85 and 70: 1 pt `sep`, labelled "A−" and "B−" in Caption 2 `label2` at the trailing edge. Day initials Caption 2. **All Time adds:** GUIDE "PB" tabs above personal-best bars; an INK "LICENSE" tab on the x-axis at the license change date. |
| 610 | Header | **"What changed since last week"** |
| 648–856 | Rows (52) | NEUTRAL plate 24 + name 17 + trailing "83" 17 Semibold + " (was 81)" 15 `label2` + 10 pt rounded triangle (▲ `great`, ▼ `okay`, none when flat). Rows: Braking ▲ · Acceleration 94 (was 89) ▲ · Cornering 89 (was 90) ▼ · Smoothness 93 (was 93), no arrow |
| 888 | Header | **"8 of 18 badges"** + trailing `tint` **"See all"** |
| 926–1040 | Badge row | Four 64 plates: Road Warrior (silver, "25"), Marathon Driver (silver), Consistent Driver (bronze), and Smooth Operator *Silver* LOCKED with 7 of 10 dots. Names in Rounded Semibold 13 under each. |
| 1072 | Header | **"You're #3 of 5 this week, up one place."** 20 Semibold `label`, 2 lines |
| 1130–1454 | Friend rows (56) | Rank 17 Bold tabular · change glyph (▲/▼ + "1" in 11, or blank) · avatar 32 · name 17 · three 16 pt top-badge silhouettes · "94" 17 Semibold + "A". The **You** row has a `fill` highlight, a silver ring and "Up 1" in 13 `label2`. Footer row **"See all time"** in `tint`. GameKit has no Month scope, so this module is always week. |
| 1486 | Header | **"Your routes"** |
| 1524–1664 | Shelf | Route cards: School run (avg 82, best 91, Improving), Practice loop (avg 89, best 94) |
| 1696–1760 | Logbook row (card, 64) | SF `book.closed` 20 + **"Logbook"** 17 Semibold over "12 h 8 m behind the wheel" 13 `label2`; trailing odometer cells **0 2 1 4 . 6** + " mi"; chevron |

### 6.5 Live HUD (874 × 402, dark only)

**Ready.** Peak: the Focus Sign + job title.
- Glass close circle 44 (`xmark`) at (62, 20).
- Left column, x 62–422:
  - y 84: **"Today's job"** 17 Semibold `label2`.
  - y 112: Focus Sign 64 + at x 142 **"Brake earlier for stops"** 28/34 Bold `label`, ≤2 lines.
  - y 200: SF `road.lanes` 22 `label` + **"Road in view"** 17 Semibold. When blocked: `road.lanes` with a slash, and **"Point the camera at the road."**
  - y 236: PERMIT tab 46×18 + **"Scoring is tuned for learners."** 15 `label2`.
  - y 292: **Start** capsule 240×72 `tintFill`, `steeringwheel` 24 + **"Start Drive"** 22 Semibold white.
- Right: camera preview 360×354 r22 at (452, 24), with two converging 2 pt `paint` dashed guides at 60% from (90, 354) and (270, 354) to (165, 160) and (195, 160).
- On Start: the Ready panel slides out leading (`.smooth(0.35)`), the Focus crossfades out in 200 ms, the car STAMPs onto the start pin, `start` haptic.

**Recording.** Peak: the live score.
- Live score **"89"** 176 Bold tabular `label` at (62, 30) + **"A−"** 56 Bold `great` (40 s hysteresis), 12 gap, baseline-aligned.
- y 236: **"12:48"** Condensed Semibold 34 `label`; 32 gap; **"4.2"** Condensed Semibold 34 + " mi" 20 `label2`.
- Hold-to-end control 128, centered at (748, 150):
  - Track ring 6 pt `fill`.
  - Disc 96, `label` at 12% opacity.
  - Glyph: rounded square 32×32 r7 in `label`.
  - **"Hold to end"** 15 Semibold `label2` at y 226.
  - Pressed: disc scales to 0.94; a 6 pt `label` ring with round caps fills **clockwise from −90°** over 0.8 s (`Circle().trim(0, p).rotation(-90°)`; verify in the simulator); `ratchet` haptic. Early release: unwinds 200 ms and the label crossfades to **"Keep holding"** for 1.5 s.
- Bottom strip: x 62–812, H28, baseline y 360. Neutral bars, ticks at buckets 12 and 34, start pin + **"3:28 PM"** 13 `label2` under it. Car M `label2` at x ≈ 463 (bucket 39). Dotted future to x 812. **No other labels.**
- Camera banner (when it applies): top-center, 44 tall, r22, `card2`, SF `video.slash` + **"Camera can't see the road. Scoring continues."** 15 Semibold. Enters with SETTLE.
- **No** Focus, plates, colored markers or event haptics.

**Saved** (speed gate: GPS >5 mph in the last 10 s, or IMU moving).
- **"Saved"** 28 Bold + **"We'll show you how it went once you're parked."** 17 `label2`.
- The completed strip, neutral, with the P plate.
- **"Done"** as a plain 17 Semibold button.
- The ledger stays unspent. The Parked notification posts after 30 s under 2 mph.

**Too short:** **"Too short to score."** / **"Drives need 2 minutes; this one was 1:24."** / Done.

### 6.6 Parked: the post-drive reveal (NEW, 874 × 402, dark only)

**Peak:** "91" + the A plate.

| Region | Spec and copy |
|---|---|
| Left, (62, 24) | **"Parked"** 28 Bold `label` + **" 3:52 PM"** Condensed Semibold 28 `label2` |
| Left, y 70–190 | **"91"** 132 Bold tabular + grade plate h64 **"A"** (`great` / `markerInk`) |
| Left, y 200 | **"+3 vs your average"** 15 Semibold `label2`. During the roll it reads "from your 88 average". |
| Right x 470–812, y 28 | Shield 24 "1" + **"School run"** 17 Semibold + BEST tab 20 (the hook) |
| Right y 64 | **"Best School run yet."** 24 Semibold `label` / **"(was 86)"** 24 Regular `label2` |
| Right y 140 | Focus verdict: plate 44 (yellow Acceleration diamond → green check) + **"Job retired. Two drives with 0 hard starts (was 3)."** 17 Regular `label`, 2 lines |
| Right y 192 | **"Next: start slowing earlier for stops."** 15 `label2` |
| Right y 222 | **"See report"** 160×50 `tintFill` capsule (17 Semibold white) + 20 gap + **"Done"** 17 Semibold `label` |
| Bottom, y 288–376 | Strip W750 H44 at x 62: markers 1–3, start pin + **"3:28 PM"**, P plate + **"3:52 PM"** (Condensed 15 `label`), car L `label` parked left of P |

- **Badge variant:** if a badge was earned, it takes the hook. A 44 plate + **"New badge: Smooth Operator, Silver"** 17 Semibold replaces the "Next:" line (the badge outranks BEST). The Badge Earned sheet follows later.
- **PB variant:** roll 88 → **98 A+**. Verdict **"Your best drive ever."** / **"(was 97)"**. The PB tab 20 STAMPs beside the plate. Caption "+10 vs your average".
- **Calm path (<70):** the grade fades in instead of stamping, the haptic is `soft`, and the verdict follows the voice rules: "A rougher one. 64, 24 under your average. Two stops did most of it."
- **Name This Route** (unnamed drives only): a system `.alert` 1 s after the reveal settles. **"Name this route?"** / **"It'll be Route 3."** TextField placeholder "School run". Buttons **Not now** / **Save**. On Save, the shield STAMPs into the Report header once.
- **Live Activity:** switches to its Parked state (6.9).

### 6.7 Share card (NEW, 1080 × 1350 px; draw at 360 × 450 pt)

Two variants: `bg` #000 and #FFF. 72 px margins. All values in px.

| y | Element |
|---|---|
| 72 | Brand mark 48 + "Drive" 40 Bold `label` (left); **"Fri, Oct 16"** 36 Regular `label2` (right) |
| 184 | Shield 96 "1" + **"School run"** 72 Bold + BEST tab (48 tall, "BEST" 30) |
| 320 | **"3:28 PM"** Condensed Semibold 96 — M-class lane line (6 px thick, dash 18, gap 12) — P plate 42 — **"3:52 PM"**. Above the line, centered: **"24 min   8.3 mi"** 40 Semibold |
| 500–720 | Strip W936 H200, L class ×3 (9 px thick, dash 24, gap 18). 54 px markers 1–3, start pin 6×54, P plate 42, car L ×3 parked. No Focus tags, no end clocks. |
| 800 | **"91"** 280 Bold + grade plate h168 r47 **"A"** (letter 100) |
| 1080 | **"Best School run yet"** 48 Semibold `label` + **" (was 86)"** `label2` |
| 1150 | ✓ (`great`) **"Job retired: easing onto the gas"** 36 Semibold `label`. Only when the drive cleared or retired a job. |
| 1230 | **"Permit · Drive 28"** 32 `label2` (left); silver Botts' dots ×2, 16 px (right) |

**Never on the share card:** a map, a route silhouette, street names or footage.

### 6.8 Driver Card (NEW, 402 × 874; Permit portrait shown)

**Peak:** the card.

- Pushed from the Profile & Settings sheet (avatar). Inline nav title **"Driver Card"**, back, trailing share.
- **Card** 240×380 at (81, 120):

  | Position | Content |
  |---|---|
  | Header band | **"Drive"** with brand mark + **"LEARNER"** |
  | (20, 68) | Photo, or car L in `bg` color on INK, 72×90 |
  | x 108 | **NAME** "Jason"; **CARD** "DRV-260604-028" |
  | y 176 | 2×2 grid: **AVG** "88" + "A−" (`great`) · **DRIVES** "28" · **BEST** "97" · **SINCE** "JUN 2026" |
  | Bottom-left | Car L 56×32 `label` |
  | Bottom-right | Silver dots ×2 |

- y 524: **"Hold the card to see your route ink."** 13 `label2`, centered. Shown on the first 3 opens only.
- y 560, inset group rows:
  - "Logbook" (chevron).
  - "Share card" in `tint`.
  - **"Got your license?"** in `tint`, which opens the alert: **"Got your license?"** / "We'll close your Permit logbook and switch scoring to licensed-driver tuning." / **Not yet** · **I got it**.
- Footer y 780: **"Drive app card. Not a government ID."** 13 `label2`, centered.
- **License version:** 358×226 at (22, 120). Header "DRIVER". Photo left; fields in a 3×2 grid on the right. Car and dots on the bottom edge.
- **Graduation frame:** the LICENSED stamp on the portrait card, then the landscape card, with the line **"From Permit to License. 28 drives and 12 hours got you here."**

### 6.9 System surfaces (board ~1320 × 820)

**Lock Screen Live Activity** (370 × ~150, padding 16)
- **Recording:**
  - Row 1: car M `label` + **"Recording"** 15 Semibold; trailing Focus Sign 20 monochrome (`label2`, static) + **"Since 3:28 PM"** 13 `label2`.
  - Row 2: **"89"** 48 Bold + **"A−"** 22 Bold (40 s hysteresis); trailing **"12 min"** Condensed Semibold 22 over **"4.2"** + " mi" Condensed 17.
  - Row 3: strip W338 H24, neutral, car M at the head, dotted future.
  - **No ticking seconds.** Minutes update on bucket commits.
- **Parked end state:**
  - Car + **"Parked 3:52 PM"**.
  - "91" 48 + "A" `great`; trailing **"Best School run yet"** 15 Semibold over "(was 86)" `label2`.
  - Completed strip in band color, P plate, car parked.
  - Dismissed after 15 min or when the app opens, ending with the session.

**Dynamic Island**
- **Compact:** leading **"89"** 15 Semibold `label` (`numericText`); trailing a 36×12 micro-strip (last 8 buckets: 2 pt neutral bars, 1.5 gap, 1.5 pt dashed baseline) with car S at the head.
- **Minimal:** car S.
- **Expanded:**
  - Leading: "89" 34 Bold + "A−" 17.
  - Trailing: "4.2 mi" Condensed 17 over "12 min" 13 `label2`.
  - Center: "Since 3:28 PM" 13 `label2`.
  - Bottom: strip H20 with car.
- **Never** shows the Focus. No `AlertConfiguration` during a drive.

**CarPlay** (`.small`): car S + **"Recording · 12 min"**. No score.

**Widgets**
- **Small, Streak** (170²):
  - "5" Rounded Bold 44 + "day streak" Rounded Semibold 15.
  - 7 dashes 16×5, gap 4.
  - **"Drive with your supervisor to make it 6."** 13 Semibold.
  - Milestone days: the mile post.
- **Small, Score:**
  - "88" 56 Bold + plate h28 "A−".
  - "30-day score" 13 `label2` / "Up 5% this week" 13 Semibold.
- **Medium, Last drive** (364×170):
  - Shield 16 + **"School run"** 15 Semibold + BEST; trailing "91" 28 Bold + "A".
  - "Fri, Oct 16" 13 `label2`.
  - Strip W332 H18 with P plate; "3:28 PM" and "3:52 PM" in 13 `label2`.
  - "24 min   8.3 mi".
- **Lock Screen rectangular:** "School run" 13 Semibold + "91 A" + a monochrome mini strip H14.
- **Lock Screen circular:** the Focus Sign, monochrome accessory rendering.
- Reloads happen only when a drive saves. Numbers use `numericText`.

### 6.10 Other screens (deltas only)

- **Sign-in:**
  - Brand mark 64 + **"Coaching for every drive, one job at a time."** 28 Bold.
  - Stock Apple / Google / Email buttons. The consent line keeps the Terms and Privacy links.
  - No plates.
- **Verify Email:** **"One tap left."** / "We sent a link to your inbox. Open it on this iPhone and you're in." **Open Mail** (`tintFill`). "Resend link" enables after 30 s, with no visible countdown.
- **Onboarding** (all static, nothing autoplays):
  - **P1** "You already know this language." Five 64 pt plates: Braking, Going, How you handle the road, Other road users, Things you earned.
  - **P2** "A clean drive is an empty road." Strip H120.
  - **P3** "One job per drive." Diamond → green plate shown side by side.
  - **P4** "Try a demo drive." Tap-triggered. 20 s of sample data through the HUD, Live Activity and Parked, labelled **"Demo drive. Sample data, nothing is recorded."**
  - **P5** "Learning or licensed?" The Driver Card assembles as portrait or landscape.
- **Badges:** header "8 of 18"; Tiered and One-time sections, 3-column grid of 72 plates.
- **Settings:** stock inset grouped.
  - Mini Driver Card header row.
  - Car row: car M + "2019 Honda Civic".
  - App Icon (named alternates).
  - Demo drive.
  - Notifications: Parked summary · Streak reminder (Permit: off) · New badges · Weekly recap Sun 7 PM · School goals.
  - Legal rows unchanged.

### 6.11 Direction board (`v2-Main.dc.html`, 1440 wide)

1. **Hero.** "Road Furniture" (Large Title ×2) + the thesis paragraph + a 1300 pt-wide canonical strip with the car parked on P.
2. **"Flighty → Drive" pairs.** Five drawn pairs, not a list: airport signage → the plate family; gate badge → Focus Sign; plane on the line → car on the strip; "Mom landed 6:32am (22m early)" → the Parked frame; Passport → Driver Card + Logbook.
3. **The grammar.** Five family columns (plates, paint, shields & posts, papers, car), each with its job sentence and drawn examples.
4. **Tokens.** The color table with light/dark swatches; the type role table set in each role.
5. **Strip anatomy.** Callouts for baseline, bars, pins, markers, tags, bracket and car.
6. **Motion and haptics legend.** Token curves; haptic glyphs: filled circle = transient (6/10/14 pt = intensity), 4-tick comb = ratchet, diamond = selection.
7. **Placement contract + DON'Ts.**

---

## 7. Motion storyboards (`v2-Motion.dc.html`)

Draw the frames side by side. Ghost cars at 25% show motion paths. Notes and haptic glyphs go in `annot` #BF5AF2 under each frame.

**M1. Live bucket commit** (HUD + Island compact; frames are 874×100 crops of the HUD bottom + 36×12 Island ×4)
- **F1, t = 0:** 38 buckets; car at bucket 38.
- **F2, 150 ms:** bucket 39 bar at 50% height, `.smooth(0.3)`; car halfway across the pitch.
- **F3, 400 ms:** bar complete; car at bucket 39 (ghost at 38). Note: "+1 pitch every 20 s, 0.4 s. Nothing moves between commits."
- **F4:** the Island compact with "88" → "89" `numericText`, and the micro-strip shifted one bar.
- Haptics: none. Reduce Motion: F1 → F3 instantly.

**M2. Hold-to-end** (frames are 160×180 crops of the control)
- **F1, 0 ms:** touch-down. Disc 0.94, ring 0%.
- **F2, 400 ms:** ring 50% from 12 o'clock, clockwise. Ratchet ticks 1–2 (0.3 / 0.45).
- **F3, 800 ms:** ring 100%. Tick 4 (1.0 / 0.8) hands off to M3.
- **F4, early release:** ring unwinding counterclockwise (200 ms); label **"Keep holding"**.
- Callout: "Starts at −90°. Verify in the simulator."
- Reduce Motion: the ring still fills (it is information); the unwind is instant.

**M3. Parked reveal** (frames at 25% = 218×100, plus the full-size final frame)
- **F1, 0–150 ms:** HUD chrome (numeral, readouts, control, banner) fades out; future dots fade; bars sink to the baseline.
- **F2, 150–750 ms (DRAW):**
  - The car appears at the start pin and drives to P. Bars rise behind its rear wheel, now in band color (`spring(0.25, bounce 0.15)` per bar).
  - Markers STAMP as the car passes them, with no haptic.
  - The score ROLLs 88 → 91, paced to finish at 700 ms.
- **F3, 750–950 ms:**
  - The P plate STAMPs and the car settles.
  - At **800 ms** the grade plate STAMPs, with **`land`** (`.success`).
  - At 950 ms the caption becomes "+3 vs your average"; the route line and verdict rise 8 pt and fade in (250 ms); the buttons fade in.
- **F4, 1150–1800 ms:**
  - 1150 ms: the Focus row fades in, then MORPHs (diamond counter-rotates 45° → 0°, yellow → green, check; 400 ms).
  - 1400 ms: the hook (BEST tab) STAMPs, with **`stamp`**.
  - 1800 ms: settled.
- **Morph sub-strip**, three 64 pt frames at 0 / 200 / 400 ms: 45° yellow diamond → 22° half-morph (fill mid-crossfade) → 0° green square with check.
- Tap anywhere: jump to the end state (150 ms crossfade, no further haptics).
- Reduce Motion: final state with a 200 ms fade; `land` kept.
- Max 2 haptics.

**M4. Rumble-strip scrub** (frames are 402×200 crops of the Report instrument)
- **F1, rest:** car at marker 1; no bubble.
- **F2, dragging over bucket 21 (okay):** bubble "7:04"; `rumbleOkay` dot (6 pt) under the bar; footage scrubbing.
- **F3, snap at marker 3:** car centered on the marker; `select` diamond glyph; readout "Hard brake 21 mph 0.33 g".
- **F4, release:** bubble fading (0.6 s); the car stays where dropped.
- Annotation row under the strip: 6 pt dots under okay bars, 10 pt under poor bars, diamonds under markers, and a curb bar at both ends.

**M5. StampLanding: Badge Earned and streak +1** (frames are 120 pt plate crops + a 244×40 dash row)
- **F1, 0 ms:** plate at 1.25×, opacity 0.
- **F2, 60 ms:** opacity 1, scale 1.15.
- **F3, ~120 ms:** contact at 1.0, `stamp` glyph.
- **F4, 320 ms:** settled. The name fades in at 200 ms. The icon-unlock row appears 200 ms later.
- **Streak strip:** Saturday's dashed outline → fill sweeping left to right (175 ms) → solid (350 ms), with the numeral 5 → 6 and `light`.
- Reduce Motion: 150 ms fades; haptics kept.

---

## 8. DON'Ts for v2

**Template patterns**
- No grey or tinted pills, chips or badges for status, category, grade or severity. That includes the v1 Focus chip, tinted grade pills and "Severe" lozenges.
- No play-triangle timestamp chips. Moments are moment tokens.
- No middle-dot metadata strings (one dot per line, max). No grey right-aligned section captions. No schema-noun headers ("Key moments", "Faults", "Insights", "Awards").
- No continuous progress bars for discrete counts: badges, streaks and goals use dots, dashes or numbers.
- No stacks of identical cards. No KPI rows. No three-pillar feature cards on the board.

**Flat constraint**
- No gradients, glow, shadows on cards, 3D, tilt/parallax, holographic effects, sheen, textures (asphalt grain, reflective sheeting), confetti, particles or ripple rings.
- The only blur allowed is system materials on chrome.

**Quiet at rest**
- No `repeatForever`, no `loop: true`, no `onAppear { withAnimation }`, no on-appear staggers, no idle car motion, no breathing elements.
- No timer-driven state changes. No per-step haptic clicks. No custom digit drums.

**Color**
- No yellow outside the Focus Sign: not on badges, the streak, the Student Driver tag, avatars, or the Dangerous card.
- No red plates. No red stop control. No green status dots.
- No blue on anything that isn't tappable. No guide green on text, numerals, bars or charts.
- No new inks. No light-mode color without a contrast check. `label3` never encodes state.

**Safety**
- Nothing on the recording HUD to read beyond the score, elapsed time, distance and the camera banner.
- No Focus while recording or in the Island.
- No band color, numbered markers or event haptics on live surfaces.
- No ticking seconds on system surfaces. No alerts during a drive. No score in CarPlay.
- No celebration while moving (the speed gate).

**Data honesty**
- No speed-limit plates and no mph on plates.
- No street names, no reverse geocoding.
- No route silhouettes or maps on share images.
- No school-goal counters ("2 of 3") until InstructorGoal has a target.
- No claims recomputed after save: verdicts are stored.
- No 1 Hz-interpolated force replay.

**Type**
- No bundled fonts. Space Grotesk and SF Mono stay retired.
- No Rounded on judged scores or headers. No Condensed below 15 pt.
- No uppercase outside plates and Driver Card field labels. No tracked caps.
- Never call `.system(size:)` directly.

**Shapes**
- No arcs, rings or gauges, apart from the hold-to-end ring (−90°, clockwise). That bans the speedometer tab icon and goal rings.
- No more than the 8 plate silhouettes.
- No second car orientation for the character. The top-down rect is only for maneuver diagrams.
- No diamond badges. No laurels outside Route Regular. The shield never means "reward".

**Voice**
- No emoji, no exclamation marks.
- No streak guilt or loss copy. No Permit streak nags by default. No notifications 8 PM – 7 AM.
- "Badges" everywhere, never "Awards".
- No tutorial captions on instruments.

**Structure**
- One share entry point: the toolbar. No bottom share capsule.
- No elapsed-time axis labels; clock times go at the strip ends.
- No custom navigation chrome.

**Process**
- Do not edit the v1 canvas files or `/home/user/drive-ios/Redesign/DriveUI`.
- Do not delete the `Animations/` workshop or the shipped Lottie JSONs without the user's confirmation; v2 just stops referencing them.

**Deferred (not drawn in v2):** force replay / friction circle, Logbook Year, school-goal counters and "Goal met", per-make car silhouettes, EU sign variants, street names.

---

**Build notes for engineering** (these constrain the design)
- **Persist at save on the session:**
  - Bucket array (10th-percentile q).
  - Clean-stretch, moving/stopped time, softest stop.
  - Verdict and BEST/PB flags.

  Per-second traces are local-only today.
- **Persist on the user:** Focus job state; badge `earnedAt` (AchievementEngine is stateless; run one chronological backfill); `licenseChangedAt` + previous license type; reveal ledger; `lastStreakAnimatedDay`; `lastSeenRank`.
- **Live Activity:**
  - Extend `ContentState` with `bars [UInt8]`, `markers [UInt8]`, `distanceM`, `parked` (~100 B).
  - Updates go out on bucket commits and integer score changes, coalesced to ≥5 s.
  - This needs a new incremental 20 s quality path; today's `DriveQuality.compute` is batch-only.
  - Live bars may differ from the final recompute; the Parked redraw absorbs that.
- **Coaching copy:** tip templates in DriveAIEngine need imperative titles and a `shortTitle` of ≤5 words.
- **Code removals:** HomeView `tilt(0.85)` and the `appeared` springs; DriveDetailType staggers; `LottieView(.weeklyEmpty/.analyzing, loop: true)` (the Parked car shows real analysis progress instead); the DriverLicenseView CMMotionManager holographic foil.
- **Checks:** add the pre-commit grep, and verify the −90° hold ring in the simulator.