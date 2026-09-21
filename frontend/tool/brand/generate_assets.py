#!/usr/bin/env python3
"""Regenerate every Kora launcher icon and native splash asset from the one
master mark, docs/brand/kora-mark.svg.

    pip install cairosvg pillow
    python3 frontend/tool/brand/generate_assets.py

Colours and placement live in brand.py. Nothing here touches Dart code or
pubspec, and the outputs are committed, so a normal build needs no Python.
"""

import json
import re

from PIL import Image

from brand import (
    FRONTEND, ICON_BG, ICON_FG, SPLASH_BG, SPLASH_FG, VIOLET_LIGHT,
    flatten, mark_svg, max_radius_units, render, rounded,
)

# Mark height as a fraction of the icon canvas.
FULL_MARK = 0.50       # iOS / legacy / web / desktop tiles
ADAPTIVE_MARK = 0.44   # inside Android's 66dp safe circle of the 108dp layer
MASKABLE_MARK = 0.46   # inside the W3C maskable safe circle (radius 40%)
SPLASH_MARK = 120      # splash mark height in dp / pt

RES = FRONTEND / "android/app/src/main/res"
DENSITY = {"mdpi": 1.0, "hdpi": 1.5, "xhdpi": 2.0, "xxhdpi": 3.0, "xxxhdpi": 4.0}


def save(im, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    im.save(path, optimize=True)


def full_icon(size, mark=FULL_MARK):
    """Opaque square tile: bg + mark."""
    return flatten(render(mark_svg(ICON_FG, size, mark, bg=ICON_BG), size), ICON_BG)


def desktop_tile(size):
    """Rounded tile for platforms that do not mask (legacy Android, Windows)."""
    return rounded(render(mark_svg(ICON_FG, size, FULL_MARK, bg=ICON_BG), size), 0.22)


def android():
    for d, f in DENSITY.items():
        # Legacy launcher icon: 48dp.
        save(desktop_tile(round(48 * f)), RES / f"mipmap-{d}/ic_launcher.png")
        layer = round(108 * f)
        save(render(mark_svg(ICON_FG, layer, ADAPTIVE_MARK), layer),
             RES / f"mipmap-{d}/ic_launcher_foreground.png")
        # Themed icon layer: opaque shape on transparency, the OS tints it.
        save(render(mark_svg("#000000", layer, ADAPTIVE_MARK), layer),
             RES / f"mipmap-{d}/ic_launcher_monochrome.png")
        # Splash icon: 288dp canvas (Android 12 clips it to a 192dp circle).
        canvas = round(288 * f)
        mh = SPLASH_MARK / 288
        save(render(mark_svg(SPLASH_FG, canvas, mh), canvas),
             RES / f"drawable-{d}/splash_icon.png")
    (RES / "mipmap-anydpi-v26").mkdir(parents=True, exist_ok=True)
    (RES / "mipmap-anydpi-v26/ic_launcher.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background"/>\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
        '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>\n'
        "</adaptive-icon>\n")
    (RES / "values/colors.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
        f'    <color name="ic_launcher_background">{ICON_BG}</color>\n'
        f'    <color name="splash_background">{SPLASH_BG}</color>\n'
        "</resources>\n")


def ios():
    base = FRONTEND / "ios/Runner/Assets.xcassets"
    contents = json.loads((base / "AppIcon.appiconset/Contents.json").read_text())
    for img in contents["images"]:
        pt = float(img["size"].split("x")[0])
        px = round(pt * int(img["scale"][0]))
        save(full_icon(px), base / "AppIcon.appiconset" / img["filename"])
    # Launch image: 160pt square canvas, mark centred, transparent (the
    # storyboard supplies the canvas colour).
    for scale, suffix in ((1, ""), (2, "@2x"), (3, "@3x")):
        px = 160 * scale
        save(render(mark_svg(SPLASH_FG, px, SPLASH_MARK / 160), px),
             base / f"LaunchImage.imageset/LaunchImage{suffix}.png")


def macos():
    base = FRONTEND / "macos/Runner/Assets.xcassets/AppIcon.appiconset"
    for n in (16, 32, 64, 128, 256, 512, 1024):
        # Big Sur template: 824/1024 rounded body, transparent margin.
        body = round(n * 824 / 1024)
        tile = rounded(render(mark_svg(ICON_FG, body, FULL_MARK, bg=ICON_BG), body), 0.2237)
        canvas = Image.new("RGBA", (n, n), (0, 0, 0, 0))
        canvas.alpha_composite(tile, ((n - body) // 2, (n - body) // 2))
        save(canvas, base / f"app_icon_{n}.png")


def web():
    web_dir = FRONTEND / "web"
    save(full_icon(48), web_dir / "favicon.png")
    for n in (192, 512):
        save(full_icon(n), web_dir / f"icons/Icon-{n}.png")
        save(full_icon(n, MASKABLE_MARK), web_dir / f"icons/Icon-maskable-{n}.png")


def windows():
    sizes = (16, 24, 32, 48, 64, 128, 256)
    ico = desktop_tile(256)
    path = FRONTEND / "windows/runner/resources/app_icon.ico"
    ico.save(path, format="ICO", sizes=[(s, s) for s in sizes])


def splash_xml():
    """Native splash configuration: solid canvas colour + centred mark."""
    layer = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        "<!-- Native launch screen shown before Flutter draws its first frame.\n"
        "     Generated assets: frontend/tool/brand/generate_assets.py -->\n"
        '<layer-list xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <item android:drawable="@color/splash_background" />\n'
        "    <item>\n"
        '        <bitmap android:gravity="center" android:src="@drawable/splash_icon" />\n'
        "    </item>\n"
        "</layer-list>\n")
    for d in ("drawable", "drawable-v21"):
        (RES / d / "launch_background.xml").write_text(layer)
    v31 = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        "<resources>\n"
        "    <!-- Android 12+ splash screen API. The icon sits inside the 192dp safe\n"
        "         circle of its 288dp canvas. -->\n"
        '    <style name="LaunchTheme" parent="@android:style/Theme.DeviceDefault.NoActionBar">\n'
        '        <item name="android:windowSplashScreenBackground">@color/splash_background</item>\n'
        '        <item name="android:windowSplashScreenAnimatedIcon">@drawable/splash_icon</item>\n'
        '        <item name="android:windowBackground">@drawable/launch_background</item>\n'
        '        <item name="android:navigationBarColor">@color/splash_background</item>\n'
        "    </style>\n"
        '    <style name="NormalTheme" parent="@android:style/Theme.DeviceDefault.NoActionBar">\n'
        '        <item name="android:windowBackground">@color/splash_background</item>\n'
        "    </style>\n"
        "</resources>\n")
    for d in ("values-v31", "values-night-v31"):
        (RES / d).mkdir(parents=True, exist_ok=True)
        (RES / d / "styles.xml").write_text(v31)


def ios_storyboard():
    p = FRONTEND / "ios/Runner/Base.lproj/LaunchScreen.storyboard"
    s = p.read_text()
    r, g, b = (int(SPLASH_BG[i:i + 2], 16) / 255 for i in (1, 3, 5))
    s = re.sub(r'<color key="backgroundColor"[^>]*/>',
               f'<color key="backgroundColor" red="{r:.4f}" green="{g:.4f}" '
               f'blue="{b:.4f}" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>', s)
    s = re.sub(r'<image name="LaunchImage" width="\d+" height="\d+"/>',
               '<image name="LaunchImage" width="160" height="160"/>', s)
    p.write_text(s)


if __name__ == "__main__":
    print("mark radius at 44% height:", round(max_radius_units("#fff", ADAPTIVE_MARK), 1),
          "of 512 (safe limit", round(512 * 66 / 108 / 2, 1), ")")
    android(); ios(); macos(); web(); windows(); splash_xml(); ios_storyboard()
    print("done")
