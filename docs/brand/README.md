# Kora brand mark

The Kora mark is a **K whose arms are an orb**: a rounded stem beside a sphere
with a mouth cut toward it. The two lobes of the orb read as the K's arms, and
the opening reads as a voice heading down the road. Two shapes, one flat colour.

- `kora-mark.svg` is the single master. Every icon and splash is generated from it.
- `concept-board.png` shows all six explored concepts, their ranking and the winner.
- `concepts/` holds each concept as SVG (kept so the captain can switch).
- `previews/` shows the result on wallpapers, at small sizes and as splash screens.

## Why this one won

Rubric, 1 to 5 each: distinctive and ownable, simple, readable at 24 px and in
one flat colour, fits the orb and violet brand, calm and premium.

| Rank | Concept | Score | Note |
|---|---|---|---|
| 1 | Speaking K (`04`, refined into `kora-mark.svg`) | 23 | Ties the name (K), the orb and voice into one form |
| 2 | Companion (`01`) | 21 | Orb with an orbiting mote. Clean, but a generic planet and moon |
| 3 | Wave-cut orb (`05`) | 19 | Lovely and on-brand, but a circle cut by a wave sits too close to the Pepsi globe |
| 4 | K + orb (`03`) | 17 | Reads as a K with a pin |
| 5 | Voice orb (`02`) | 16 | An equaliser, not ownable |
| 6 | Horizon (`06`) | 15 | Reads as a sunset or a lamp |

The first cut of the winner looked like Pac-Man. Moving the mouth's apex up
against the stem and narrowing the angle to 76 degrees made it read as a K
first and an orb second, and that fixed it. Rule of thumb for future edits: if
the apex drifts toward the orb's centre, the Pac-Man reading comes back.

## Construction

Master canvas 512 x 512, mark bounding box 262 x 280 centred on the canvas.

| Part | Geometry |
|---|---|
| Stem | Pill, 58 wide x 280 tall, fully rounded ends |
| Orb | Circle of visual radius 140 (path radius 130 plus a 10 unit round stroke), so it is exactly as tall as the stem (280) |
| Mouth | Wedge with its apex 10 units in from the orb's left edge, opening right at plus and minus 38 degrees (76 degrees total). Tips are softened by the 10 unit round join |
| Gap | 22 units between stem and orb (about 8 percent of mark height) |
| Colour | One flat colour. Master file uses `#C4B5FD` |

## Colour

| Use | Colour |
|---|---|
| Mark on dark (splash, in-app) | `#C4B5FD` (`KoraColors.primaryLight`) on `#07060B` (`KoraColors.canvas`) |
| App icon | `#F4F1FF` (`KoraColors.textPrimary`) on `#8B5CF6` (`KoraColors.primary`) |
| Mark on light | `#8B5CF6`, or `#1B1538` for a flat ink version |
| Monochrome (Android themed, notification) | any single opaque colour, the OS tints it |

Never use lime `#C8F250` or any yellow-green anywhere in the mark or icon. It
is reserved for the mic-is-live indicator.

The launcher icon is a violet tile on purpose. A dark tile disappears on dark
wallpapers, and a violet one stays visible on both light and dark.

## Clear space and minimum size

- Clear space: the stem width (58 units, about 20 percent of the mark's height) on every side.
- Minimum size: 16 px tall (favicon). Below 24 px use the flat single-colour version.
- Splash: mark 120 dp (Android) or 120 pt (iOS) tall, centred.

## Do and don't

Do: use the master SVG, keep the two shapes and the 22 unit gap, keep it flat.

Don't:
- add gradients, glows, shadows or outlines to the mark
- rotate, skew, stretch or re-space the stem and orb
- recolour it lime, or use two colours inside the mark
- place lettering inside the mark; a wordmark, if ever needed, is Plus Jakarta Sans and sits outside the clear space
- put the light `#C4B5FD` mark on a light background

## Regenerating everything

```
pip install cairosvg pillow
python3 frontend/tool/brand/generate_assets.py   # icons + splash, all platforms
python3 frontend/tool/brand/make_previews.py     # concept board + previews
```

Colours and placement are constants in `frontend/tool/brand/brand.py` and
`generate_assets.py`. The generated files are committed, so building the app
needs no Python. No Flutter package was added: a launcher-icon or native-splash
package would only wrap the same PNG output while touching `pubspec.lock`.

## Generated files

- Android: `mipmap-*/ic_launcher.png` (legacy), `ic_launcher_foreground.png`, `ic_launcher_monochrome.png`, `mipmap-anydpi-v26/ic_launcher.xml`, `drawable-*dpi/splash_icon.png`, `drawable*/launch_background.xml`, `values/colors.xml`, `values*/styles.xml`, `values-v31/`, `values-night-v31/`
- iOS: `AppIcon.appiconset` (opaque, every size in its `Contents.json`), `LaunchImage.imageset`, `LaunchScreen.storyboard`
- macOS: `AppIcon.appiconset` (rounded body on a transparent margin)
- Web: `favicon.png`, `icons/Icon-192.png`, `Icon-512.png`, maskable 192 and 512, `manifest.json`
- Windows: `runner/resources/app_icon.ico` (16 to 256)

## Native splash

Background is `#07060B`, the same as `KoraColors.canvas`, which is what the
first Flutter screen paints (the onboarding splash uses the transparent
editorial mood over the canvas glow), so there is no colour flash on hand-off.

## Names

Changed to `Kora`: Android `android:label`; `MaterialApp.title` (task switcher);
iOS `CFBundleDisplayName`, `CFBundleName` and the three permission prompts that
said "VoiceOps"; macOS `CFBundleDisplayName` (added); web `<title>`, Apple web
app title, meta description, `manifest.json` `name`, `short_name` and
description; Windows `ProductName`, `FileDescription` and the window title.

Deliberately left: Dart package `name: voiceops`; `com.example.voiceops` and
`io.voiceops.app` ids; Android `namespace` and `applicationId`; macOS
`PRODUCT_NAME = voiceops` (the Xcode scheme and bundle path depend on it, the
display name is set separately); Windows `InternalName` and `OriginalFilename`
`voiceops.exe` (must match the CMake binary name); signing, Firebase and
Supabase configuration.
