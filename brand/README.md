# Hmmm — brand assets

Two pieces of artwork do everything.

**Monogram** — the `H` followed by a three-shoulder arcade at cap height. Ink extent **124 × 56** drawing units (2.2:1). Use wherever the identity appears at readable size: splash, letterhead, repo header, documentation.

**Wordmark** — the full `Hmmm`, the three `m`s drawn as separate letters with a **third shoulder on the final `m`** in the accent, so the name trails off in the letterform itself rather than in a graphic. Ink extent **244 × 56**.

**Arcade** — the monogram's arcade with no `H`, **73 × 56**. This is the launcher icon: at 28px the `H` costs a third of the width and the launcher already shows the name.

## Grid

One unit = 1/56 of the cap height. Stem 7. `H` 40 wide, stems at x0 and x33, crossbar `y24.5 h7`. Arcade stems 22 apart, shoulders spring at `y3.5` and turn down on a 10-unit radius at `y13.5`. Gap between `H` and arcade: 11. Every stroke is width 7, butt cap, no rounding.

**Clear space** = 1 cap height (56 units) on all four sides, measured from the ink bounds.

**Minimum sizes** — monogram 88px / 22mm wide; wordmark 120px / 30mm (below that the trailing shoulder closes up); arcade 24px.

## Colour

| Context | Ink | Accent |
| --- | --- | --- |
| Light | `#16150F` | `#5B3492` |
| Dark | `#F5F4EE` | `#C29BF2` |
| Print / monochrome | `#000000` | `#000000` |

The accent is the app's **action** colour, so the brand borrows from the interface's controls rather than its data. It is always the **final shoulder** — never a whole arch run, never the `H`.

One honest caveat: in dark mode `#C29BF2` is also lane L3's colour, so a user with three medications sees a dashed band in the brand colour. Acceptable, because the mark is never a band — it is a letterform at cap height, and lanes are identified by texture and `L`-label regardless. **Do not resolve this by re-hueing L3**: §02 of the design spec balances an L1×L3 deutan collision against those exact values.

In monochrome the final shoulder is identified by **position**, not hue. That is why the accent is a shoulder and not a separate object.

## Files

| File | Use |
| --- | --- |
| `monogram-{ink,dark,black}.svg` | primary mark, 124 × 56 |
| `wordmark-{ink,dark,black}.svg` | full name, 244 × 56 |
| `arcade-{ink,dark,black}.svg` | icon artwork, 73 × 56 |
| `play_icon_512.png` | Play Store listing icon; arcade at 85% of frame width, no baked rounding, no shadow |
| `repo-banner.png` | 1280 × 640 (2× of 640 × 320), dark ground |
| `letterhead.svg` | PDF report header; all black. Substitute `{{EXPORT_DATE}}`, `{{RANGE}}`, `{{MED_1}}`, `{{MED_2}}` |
| `android/ic_launcher_foreground.xml` | adaptive foreground — **fitted to the 66dp safe circle**, see below |
| `android/ic_launcher_foreground_dark.xml` | dark-theme foreground |
| `android/ic_launcher_monochrome.xml` | themed-icon layer (Android 13+) |
| `android/ic_launcher_background{,_dark}.xml` | flat `#F4F2EC` / `#1C1C19` |
| `android/ic_launcher.xml` | `mipmap-anydpi-v26/` adaptive-icon config |
| `android/splash_icon_{light,dark}.xml` | monogram centred on the 288dp splash canvas |
| `android/themes_splash.xml` | `Theme.SplashScreen` fragment + the colour it needs |

## The launcher constraint — do not "fix" this

The foreground is `translate(27.90 33.98) scale(0.715)` on the 108 viewport, giving ink of **52.2 × 40.0** centred at (54, 54).

That looks small against the 72dp safe *square*, and it is deliberate. Android masks adaptive layers to a **72dp viewport**, so a circular mask leaves r=36 and Google's guaranteed-visible circle is 66dp (**r=33**). The arcade's corner sits **46 units** from centre unscaled — a square-fit version (`scale(0.98)`) has **both outer stems sliced off on any circular launcher mask**, which is most Pixels. At `scale(0.715)` the corners land 32.9 units out, inside r=33 with ~0.1dp spare.

The Play Store icon is **not** an adaptive layer and does not inherit this: it is a square asset Google rounds itself, so it uses its own fit (`scale(1.26)`, 92 × 70.6 of the 108 grid).

## Never

Re-space the `H` and arcade · change the monogram's shoulder count (three, always) · tilt, outline, or add effects · set either mark in a typeface — they are drawn artwork · put the accent on anything but the final shoulder · use the monogram below its minimum size instead of the arcade.
