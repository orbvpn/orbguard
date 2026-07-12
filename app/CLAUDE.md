# OrbGuard App — Design System (2026 OrbVPN Brand Kit)

The app shares the OrbVPN brand kit: **Volt Lime + Cyber Pink on obsidian/cloud,
Apple-style liquid glass**. There is ONE source of truth for every color, radius,
shadow, blur, font, and spacing value:

| File (lib/presentation/theme/) | Role |
| --- | --- |
| `brand.dart` | `Brand` tokens (theme-aware getters), `BrandText` type recipes, `BrandGlass`/`BrandGlassCircle`/`BrandBed` surfaces, `GlassTopEdgePainter` |
| `colors.dart` | `AppColors` — all color tokens: brand fills, ink getters, severity ramp, chart palette, surfaces |
| `app_theme.dart` | Material `ThemeData` (light+dark) built from the tokens; `context.colors/text/isDark/onSurface/onSurfaceMuted` |
| `glass_theme.dart` | `GlassTheme` glass constants + decoration factories + `GlassContainer`/`GlassCircleButton`/`GlassPillContainer`/`GlassGradientBackground` |
| `spacing.dart` | `AppSpacing` scale, `VerticalGap`/`HorizontalGap`/`ScreenPadding` |

`AppColors.uiBrightness` is synced in `MaterialApp.builder` (main.dart) — every
`Brand.*`/ink getter flips with the theme automatically. Never bypass it.

## Non-negotiable rules (from the kit)

1. **One lime action per screen** — the single primary intent; all else glass/neutral.
2. **Pink punctuates** — alerts, live indicators, small accents. Never large pink fills.
3. **Obsidian/cloud leads** — generous background is the trust signal.
4. **Glass over color** — glass sits on the BrandBed washes, never on flat.
5. **Lime is fill-only** — `Brand.onLime` (#08080A) text ON lime; for lime-colored
   TEXT/ICONS use `AppColors.accentInk` (deep lime on light). Same for pink →
   `secondaryInk`, red → `errorInk`, gold → `amberInk`.

## Key values

- Fills: lime `#C6FF3D` · pink `#FF3DA6` · danger `#FF5C6C`/`#E0354A` · gold `#FFB800`
- Surfaces: bg `#08080A`/`#F4F5F1` · surface `#131316`/`#FFFFFF` · surface2 `#1C1C21`/`#ECEDE7`
- Glass: fill white .08 (dark)/.55 (light) · border white .18 / `#12121C`.08 @1px ·
  blur 24/22 + saturate(1.55/1.50) · shadow `0 24 50 rgba(0,0,0,.45)` / `0 18 40 rgba(20,20,45,.12)`
- Radii: `GlassTheme.radiusPill 38 / Large 24 / Medium 16 / Small 12 / XSmall 8`; `Brand.rSm 11 / rMd 14 / rLg 22`
- Type: display/headings = **Archivo** (`BrandText.display/h2/heading`), body/UI =
  **IBM Plex Sans** (`BrandText.title/body`), labels/data = **IBM Plex Mono**
  (`BrandText.label/mono`). All bundled in `assets/fonts/` — no runtime fetch.
- Severity ramp: `AppColors.severityCritical #E0354A / High #FF5C6C / Medium #FF3DA6 /
  Low #FFB800 / Info #9A9CA6`. Charts: `AppColors.chartColors` (spectrum family).

## Rules for new code

- NEVER hardcode a color (`Colors.*`, `Color(0x…)`), radius, shadow, or font — use the
  tokens. Exceptions: `Colors.transparent`, and third-party vendor colors tagged
  `// vendor identity`.
- Severity/status colors in providers/models resolve from `AppColors.*.toARGB32()` —
  keep it that way so a token change recolors everything.
- New screens: `GlassPage` (or `GlassTabPage` for tabbed) — never raw `Scaffold` with a
  hand-built header. Cards: `GlassCard`/`GlassContainer`/`BrandGlass`. CTAs: `BrandButton`
  or the themed `ElevatedButton` (already lime with kit hover/pressed/disabled states).
- Nav/tab/chip selected states: `Brand.navActive` + `Brand.navActivePill` (only the
  active item takes lime).
- `Brand.*` and `AppColors.*Ink/accentPill/text2` getters are NOT const — don't put
  them inside `const` expressions.
