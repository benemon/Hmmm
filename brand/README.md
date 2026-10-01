# Hmmm brand assets

Three pieces of artwork cover every use.

**Monogram**: the `H` followed by a three-shoulder arcade at cap height. Ink extent 124 × 56 drawing units (2.2:1). Use wherever the identity appears at readable size: splash, letterhead, documentation.

**Wordmark**: the full `Hmmm`, the three `m`s drawn as separate letters with a third shoulder on the final `m` in the accent. Ink extent 244 × 56. This is the repo header.

**Arcade**: the monogram's arcade with no `H`, 73 × 56. This is the launcher icon. At 28px the `H` would cost a third of the width, and the launcher already shows the name.

## Grid

One unit = 1/56 of the cap height. Stem 7. `H` 40 wide, stems at x0 and x33, crossbar `y24.5 h7`. Arcade stems 22 apart, shoulders spring at `y3.5` and turn down on a 10-unit radius at `y13.5`. Gap between `H` and arcade: 11. Every stroke is width 7, butt cap, no rounding.

Clear space is 1 cap height (56 units) on all four sides, measured from the ink bounds.

Minimum sizes: monogram 88px / 22mm wide; wordmark 120px / 30mm (below that the trailing shoulder closes up); arcade 24px.

## Colour

| Context | Ink | Accent |
| --- | --- | --- |
| Light | `#16150F` | `#5B3492` |
| Dark | `#F5F4EE` | `#C29BF2` |
| Print / monochrome | `#000000` | `#000000` |

The accent is the app's action colour. It is applied to the final shoulder only, never to a whole arch run or to the `H`.

In dark mode `#C29BF2` is also the purple band swatch, the default for a third medication, so the brand colour can appear on a dashed band. The mark is a letterform at cap height, never a band, and bands are identified by texture and medication name. **Do not resolve this by re-hueing the purple swatch.** The default blue and purple bands were chosen to stay separable under deutan colour vision. Band colours are user-chosen, so this holds for the defaults only.

In monochrome the final shoulder is identified by position.

## Files

| File | Use |
| --- | --- |
| `monogram-{ink,dark,black}.svg` | primary mark, 124 × 56 |
| `wordmark-{ink,dark,black}.svg` | full name, 244 × 56 |
| `arcade-{ink,dark,black}.svg` | icon artwork, 73 × 56 |
| `play_icon_512.png` | Play Store listing icon; arcade at 85% of frame width, no baked rounding, no shadow |
| `repo-banner.png` | 1280 × 640 (2× of 640 × 320), dark ground |
| `letterhead.svg` | PDF report header; all black. The report substitutes `{{EXPORT_DATE}}` and `{{RANGE}}`, removes the placeholder legend group, and draws the medication legend from data |
| `android/ic_launcher_foreground.xml` | adaptive foreground, fitted to the 66dp safe circle (see Launcher scale) |
| `android/ic_launcher_foreground_dark.xml` | dark-theme foreground |
| `android/ic_launcher_monochrome.xml` | themed-icon layer (Android 13+) |
| `android/ic_launcher_background{,_dark}.xml` | flat `#F4F2EC` / `#1C1C19` |
| `android/ic_launcher.xml` | `mipmap-anydpi-v26/` adaptive-icon config |
| `android/splash_icon_{light,dark}.xml` | monogram centred on the 288dp splash canvas |
| `android/themes_splash.xml` | `Theme.SplashScreen` fragment + the colour it needs |

## Launcher scale

The foreground is `translate(27.90 33.98) scale(0.715)` on the 108 viewport, giving ink of 52.2 × 40.0 centred at (54, 54). Do not enlarge it.

The [adaptive icon](https://developer.android.com/develop/ui/views/launch/icon_design_adaptive) safe zone is a 66dp circle, r=33 on the 108 grid. The arcade's corner sits 46 units from centre unscaled. A square-fit version (`scale(0.98)`) loses both outer stems on a circular launcher mask. At `scale(0.715)` the corners land 32.9 units out, inside r=33 with about 0.1dp spare.

The Play Store icon is not an adaptive layer. It is a square asset that [Google Play rounds](https://developer.android.com/distribute/google-play/resources/icon-design-specifications), so it uses its own fit (`scale(1.26)`, 92 × 70.6 of the 108 grid).

## Never

- Re-space the `H` and arcade.
- Change the monogram's shoulder count. It is three.
- Tilt, outline, or add effects.
- Set either mark in a typeface. Both are drawn artwork.
- Put the accent on anything but the final shoulder.
- Use the monogram below its minimum size instead of the arcade.
