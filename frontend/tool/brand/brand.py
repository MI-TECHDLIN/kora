"""Shared helpers for the Kora brand tools: the master mark, colours and rendering.

Requires Python 3.9+, `cairosvg` and `pillow` (dev tooling only, nothing ships
in the Flutter app):  pip install cairosvg pillow
"""

import io
import re
from pathlib import Path

import cairosvg
from PIL import Image

ROOT = Path(__file__).resolve().parents[3]  # repo root
FRONTEND = ROOT / "frontend"
BRAND_DOCS = ROOT / "docs" / "brand"
MASTER_SVG = BRAND_DOCS / "kora-mark.svg"

# Palette (mirrors frontend/lib/core/theme/tokens.dart). Lime is never used.
CANVAS = "#07060B"  # KoraColors.canvas, the app's first-screen background
VIOLET = "#8B5CF6"  # KoraColors.primary
VIOLET_LIGHT = "#C4B5FD"  # KoraColors.primaryLight, the master mark colour
INK_WHITE = "#F4F1FF"  # KoraColors.textPrimary

# Launcher icon: violet tile, near-white mark. Reads on light and dark wallpapers.
ICON_BG = VIOLET
ICON_FG = INK_WHITE
# Splash: canvas background, lavender mark.
SPLASH_BG = CANVAS
SPLASH_FG = VIOLET_LIGHT

_MASTER_COLOR = "#C4B5FD"
_MARK_BODY = re.search(
    r'(<g id="mark".*?</g>)', MASTER_SVG.read_text(), re.S
).group(1)

CANVAS_UNITS = 512
MARK_HEIGHT_UNITS = 280  # stem height in the master, the mark's visual height


def mark_svg(color: str, size: int, mark_height: float, bg: str | None = None,
             dx: float = 0, dy: float = 0) -> str:
    """A square SVG of `size` px with the mark scaled so its height is
    `mark_height` (fraction of the canvas), centred, on `bg` (or transparent)."""
    s = mark_height * CANVAS_UNITS / MARK_HEIGHT_UNITS
    body = _MARK_BODY.replace(_MASTER_COLOR, color)
    bg_rect = f'<rect width="512" height="512" fill="{bg}"/>' if bg else ""
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" '
        f'width="{size}" height="{size}">{bg_rect}'
        f'<g transform="translate({256 + dx} {256 + dy}) scale({s}) translate(-256 -256)">'
        f"{body}</g></svg>"
    )


def render(svg: str, size: int) -> Image.Image:
    png = cairosvg.svg2png(
        bytestring=svg.encode(), output_width=size, output_height=size
    )
    return Image.open(io.BytesIO(png)).convert("RGBA")


def flatten(im: Image.Image, bg: str) -> Image.Image:
    """Composite over an opaque background and return an RGB image."""
    base = Image.new("RGBA", im.size, bg)
    base.alpha_composite(im)
    return base.convert("RGB")


def rounded(im: Image.Image, radius_frac: float) -> Image.Image:
    """Clip to a rounded square (legacy launchers, macOS, Windows, previews)."""
    from PIL import ImageDraw

    n = im.width
    k = 4  # supersample the mask for clean edges
    mask = Image.new("L", (n * k, n * k), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, n * k - 1, n * k - 1), radius=radius_frac * n * k, fill=255
    )
    out = im.copy()
    out.putalpha(mask.resize((n, n), Image.LANCZOS))
    return out


def max_radius_units(color: str = "#fff", mark_height: float = 1.0) -> float:
    """Farthest opaque pixel from the canvas centre, in 512-unit space, for the
    mark at `mark_height`. Used to keep the mark inside safe zones."""
    im = render(mark_svg(color, 1024, mark_height), 1024)
    a = im.getchannel("A").point(lambda v: 255 if v > 8 else 0)
    px = a.load()
    best = 0.0
    for y in range(0, 1024, 2):
        for x in range(0, 1024, 2):
            if px[x, y]:
                best = max(best, ((x - 512) ** 2 + (y - 512) ** 2) ** 0.5)
    return best / 2  # 1024px -> 512 units
