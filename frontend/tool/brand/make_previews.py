#!/usr/bin/env python3
"""Render docs/brand/concept-board.png and docs/brand/previews/*.png.

The previews read the REAL generated assets from frontend/, so they show what
ships. Run generate_assets.py first.  Needs cairosvg + pillow.
"""

from PIL import Image, ImageDraw, ImageFont

from brand import (
    BRAND_DOCS, CANVAS, FRONTEND, ICON_BG, VIOLET, VIOLET_LIGHT,
    mark_svg, render, rounded,
)

RES = FRONTEND / "android/app/src/main/res"
OUT = BRAND_DOCS / "previews"


def font(size, bold=False):
    name = "DejaVuSans-Bold.ttf" if bold else "DejaVuSans.ttf"
    try:
        return ImageFont.truetype(f"/usr/share/fonts/truetype/dejavu/{name}", size)
    except OSError:
        return ImageFont.load_default(size)


def gradient(size, top, bottom):
    w, h = size
    im = Image.new("RGB", size)
    d = ImageDraw.Draw(im)
    for y in range(h):
        t = y / (h - 1)
        d.line([(0, y), (w, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
    return im


def adaptive_icon(px, shape="circle"):
    """The real adaptive layers, masked the way a launcher would show them."""
    fg = Image.open(RES / "mipmap-xxxhdpi/ic_launcher_foreground.png").convert("RGBA")
    layer = Image.new("RGBA", fg.size, ICON_BG)
    layer.alpha_composite(fg)
    vis = round(fg.width * 72 / 108)  # launchers show the central 72dp
    o = (fg.width - vis) // 2
    layer = layer.crop((o, o, o + vis, o + vis)).resize((px, px), Image.LANCZOS)
    k = 4
    m = Image.new("L", (px * k, px * k), 0)
    dm = ImageDraw.Draw(m)
    if shape == "circle":
        dm.ellipse((0, 0, px * k - 1, px * k - 1), fill=255)
    else:
        dm.rounded_rectangle((0, 0, px * k - 1, px * k - 1), radius=px * k * 0.3, fill=255)
    layer.putalpha(m.resize((px, px), Image.LANCZOS))
    return layer


def ios_icon(px):
    im = Image.open(FRONTEND / "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png")
    im = im.convert("RGBA").resize((px, px), Image.LANCZOS)
    return rounded(im, 0.2237)


def dummy(px, color):
    return rounded(Image.new("RGBA", (px, px), color), 0.26)


def wallpaper_panel(kind):
    W, H = 900, 640
    if kind == "light":
        bg = gradient((W, H), (238, 226, 214), (196, 214, 236))
        label, tile, txt = "Light wallpaper", (255, 255, 255, 120), (30, 30, 40)
    else:
        bg = gradient((W, H), (24, 20, 44), (6, 8, 20))
        label, tile, txt = "Dark wallpaper", (255, 255, 255, 40), (235, 235, 245)
    bg = bg.convert("RGBA")
    d = ImageDraw.Draw(bg)
    d.text((28, 22), label, fill=txt, font=font(22, True))
    size = 132
    cols, rows = 4, 2
    x0 = (W - cols * size - (cols - 1) * 48) // 2
    for r in range(rows):
        for c in range(cols):
            x, y = x0 + c * (size + 48), 100 + r * (size + 96)
            if (r, c) == (0, 1):
                icon, name = adaptive_icon(size, "circle"), "Kora"
            elif (r, c) == (0, 2):
                icon, name = adaptive_icon(size, "squircle"), "Kora"
            elif (r, c) == (1, 1):
                icon, name = ios_icon(size), "Kora"
            else:
                icon, name = dummy(size, tile), ["Maps", "", "", "Mail", "Notes", "", "", "Clock"][r * cols + c]
            bg.alpha_composite(icon, (x, y))
            f = font(20)
            tw = d.textlength(name, font=f)
            d.text((x + (size - tw) / 2, y + size + 12), name, fill=txt, font=f)
    cap = font(16)
    d.text((28, H - 44), "Android circle and squircle masks (adaptive), iOS rounded square", fill=txt, font=cap)
    return bg.convert("RGB")


def small_sizes():
    W, H = 1100, 520
    im = Image.new("RGB", (W, H), "#101018")
    d = ImageDraw.Draw(im)
    light = Image.new("RGB", (W // 2, H), "#ECEAF2")
    im.paste(light, (W // 2, 0))
    rows = [("Launcher 48 / 72 / 96 px", (96, 72, 48)), ("Task switcher, notification 32 / 24 / 16 px", (32, 24, 16))]
    icon_src = Image.open(FRONTEND / "web/icons/Icon-512.png").convert("RGBA")
    for panel, (x0, ink) in enumerate(((0, "#EDEBF5"), (W // 2, "#1B1538"))):
        d.text((x0 + 30, 24), "Dark surface" if panel == 0 else "Light surface", fill=ink, font=font(22, True))
        y = 90
        for title, sizes in rows:
            d.text((x0 + 30, y), title, fill=ink, font=font(16))
            x = x0 + 30
            for s in sizes:
                tile = rounded(icon_src.resize((s, s), Image.LANCZOS), 0.22)
                im.paste(tile, (x, y + 34), tile)
                x += s + 28
            y += 170
        # Notification / status bar: the silhouette is white on dark, ink on light.
        mono = render(mark_svg("#FFFFFF" if panel == 0 else "#1B1538", 96, 0.62), 96)
        d.text((x0 + 30, 360), "Monochrome 48 / 24 px", fill=ink, font=font(16))
        for i, s in enumerate((48, 24)):
            m = mono.resize((s, s), Image.LANCZOS)
            im.paste(m, (x0 + 30 + i * 80, 396), m)
        # Android 13 themed icon: tinted circle with the monochrome layer
        mono_layer = Image.open(RES / "mipmap-xxxhdpi/ic_launcher_monochrome.png").convert("RGBA")
        tint = (208, 188, 255) if panel == 0 else (103, 80, 164)
        bgc = (56, 30, 114) if panel == 0 else (234, 221, 255)
        circ = Image.new("RGBA", mono_layer.size, bgc + (255,))
        solid = Image.new("RGBA", mono_layer.size, tint + (255,))
        circ.paste(solid, mask=mono_layer.getchannel("A"))
        vis = round(mono_layer.width * 72 / 108)
        o = (mono_layer.width - vis) // 2
        circ = circ.crop((o, o, o + vis, o + vis)).resize((96, 96), Image.LANCZOS)
        k = 4
        mk = Image.new("L", (96 * k, 96 * k), 0)
        ImageDraw.Draw(mk).ellipse((0, 0, 96 * k - 1, 96 * k - 1), fill=255)
        circ.putalpha(mk.resize((96, 96), Image.LANCZOS))
        im.paste(circ, (x0 + 330, 380), circ)
        d.text((x0 + 330, 350), "Themed (Android 13)", fill=ink, font=font(16))
    return im


def phone(content, w=300, h=620, radius=44):
    """Phone-shaped frame around `content` (already w x h)."""
    pad = 12
    frame = Image.new("RGBA", (w + 2 * pad, h + 2 * pad), (0, 0, 0, 0))
    k = 3
    m = Image.new("L", (frame.width * k, frame.height * k), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, frame.width * k - 1, frame.height * k - 1), radius=(radius + pad) * k, fill=255)
    frame.paste(Image.new("RGBA", frame.size, "#2A2740"), mask=m.resize(frame.size, Image.LANCZOS))
    sm = Image.new("L", (w * k, h * k), 0)
    ImageDraw.Draw(sm).rounded_rectangle((0, 0, w * k - 1, h * k - 1), radius=radius * k, fill=255)
    frame.paste(content.convert("RGBA"), (pad, pad), sm.resize((w, h), Image.LANCZOS))
    return frame


def splash_phones():
    w, h = 300, 620
    # Android: 288dp icon canvas drawn at 1 dp = 300/412 px on a 412dp wide phone.
    scale = w / 412
    android = Image.new("RGB", (w, h), CANVAS)
    sp = Image.open(RES / "drawable-xxxhdpi/splash_icon.png").convert("RGBA")
    px = round(288 * scale)
    sp = sp.resize((px, px), Image.LANCZOS)
    a = android.convert("RGBA")
    a.alpha_composite(sp, ((w - px) // 2, (h - px) // 2))
    # Android 12: also show the 192dp safe circle as a faint guide on a second phone
    a12 = a.copy()
    dd = ImageDraw.Draw(a12)
    r = 96 * scale
    dd.ellipse((w / 2 - r, h / 2 - r, w / 2 + r, h / 2 + r), outline=(255, 255, 255, 40), width=1)
    ios = Image.new("RGBA", (w, h), CANVAS)
    li = Image.open(FRONTEND / "ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@3x.png").convert("RGBA")
    px2 = round(160 * (w / 390))
    li = li.resize((px2, px2), Image.LANCZOS)
    ios.alpha_composite(li, ((w - px2) // 2, (h - px2) // 2))
    W = 3 * (w + 24) + 100
    sheet = Image.new("RGB", (W, h + 140), "#15131f")
    d = ImageDraw.Draw(sheet)
    for i, (im, cap) in enumerate(((a, "Android (launch_background)"), (a12, "Android 12+ (safe circle guide)"), (ios, "iOS (LaunchScreen)"))):
        x = 40 + i * (w + 24 + 10)
        sheet.paste(phone(im, w, h), (x, 40), phone(im, w, h))
        d.text((x, h + 80), cap, fill="#C4B5FD", font=font(15))
    return sheet


def concept_board():
    concepts = [
        ("01-companion", "Companion", "Orb with an orbiting mote in a bite. Clean, but a generic planet-and-moon.", (3, 5, 5, 4, 4)),
        ("02-voice-orb", "Voice orb", "Bars that trace a sphere. Reads as an equaliser, not ownable.", (2, 3, 4, 4, 3)),
        ("03-k-orb", "K + orb", "K monogram with an orb terminal. Reads as a K with a pin.", (3, 4, 4, 3, 3)),
        ("04-speaking-k", "Speaking K, 1st cut", "Stem + orb with a mouth. Winner direction, refined into kora-mark.svg.", (5, 5, 4, 5, 4)),
        ("05-wave-orb", "Wave-cut orb", "Sphere split by a voice wave. Lovely, but close to the Pepsi globe.", (2, 5, 3, 5, 4)),
        ("06-horizon", "Horizon", "Orb over a wave line. Reads as a sunset or lamp.", (3, 3, 2, 3, 4)),
    ]
    crit = "Distinct / Simple / 24px / Orb fit / Calm"
    cw, ch = 520, 690
    cols = 3
    W, H = cols * cw, 140 + 2 * ch + 380
    board = Image.new("RGB", (W, H), "#0B0A14")
    d = ImageDraw.Draw(board)
    d.text((40, 30), "Kora logo concepts", fill="#F4F1FF", font=font(40, True))
    d.text((40, 88), f"Rubric, 1-5 each ({crit}). Ranked below.", fill="#A7A1C4", font=font(20))

    def tinted(name, color, size):
        svg = (BRAND_DOCS / "concepts" / f"{name}.svg").read_text().replace(VIOLET, color)
        return render(svg, size)

    ranked = sorted(concepts, key=lambda c: -sum(c[3]))
    for i, (name, title, note, scores) in enumerate(ranked):
        x0, y0 = (i % cols) * cw, 140 + (i // cols) * ch
        d.rounded_rectangle((x0 + 20, y0, x0 + cw - 20, y0 + ch - 24), 24, fill="#12101F", outline="#26223D")
        d.text((x0 + 44, y0 + 22), f"#{i + 1}  {title}", fill="#F4F1FF", font=font(24, True))
        d.text((x0 + cw - 120, y0 + 26), f"{sum(scores)}/25", fill=VIOLET_LIGHT, font=font(22, True))
        big = tinted(name, VIOLET_LIGHT, 240)
        board.paste(big, (x0 + (cw - 240) // 2, y0 + 70), big)
        # small sizes on dark and light, plus flat black
        y = y0 + 330
        for label, bgc, col, ink in (("dark", "#07060B", VIOLET_LIGHT, "#A7A1C4"), ("light", "#F4F1FF", VIOLET, "#4F4677"), ("flat", "#FFFFFF", "#111111", "#4F4677")):
            d.rounded_rectangle((x0 + 44, y, x0 + cw - 44, y + 62), 12, fill=bgc)
            xx = x0 + 60
            for s in (48, 32, 24, 16):
                ic = tinted(name, col, s)
                board.paste(ic, (xx, y + (62 - s) // 2), ic)
                xx += s + 22
            d.text((x0 + cw - 130, y + 20), label, fill=ink, font=font(16))
            y += 74
        # wrap the note
        words, line, ty = note.split(), "", y + 6
        for w_ in words:
            if d.textlength(line + " " + w_, font=font(16)) > cw - 110:
                d.text((x0 + 44, ty), line, fill="#A7A1C4", font=font(16)); ty += 22; line = w_
            else:
                line = (line + " " + w_).strip()
        d.text((x0 + 44, ty), line, fill="#A7A1C4", font=font(16))
        d.text((x0 + 44, ty + 30), "Distinct %d  Simple %d  24px %d  Orb %d  Calm %d" % scores, fill="#7C7797", font=font(16))
    # Winner, refined
    y0 = 140 + 2 * ch
    d.rounded_rectangle((20, y0, W - 20, y0 + 340), 24, fill="#12101F", outline=VIOLET)
    d.text((44, y0 + 20), "Winner, refined: kora-mark.svg", fill="#F4F1FF", font=font(26, True))
    d.text((44, y0 + 60), "A K whose arms are one orb. Two shapes, one flat colour, readable at 16 px.", fill="#A7A1C4", font=font(18))
    d.text((44, y0 + 88), "Stem + orb with a 76 degree mouth aimed at the stem: a voice opening toward the road.", fill="#A7A1C4", font=font(18))
    x = 44
    for s, bgc, col in ((200, "#07060B", VIOLET_LIGHT), (200, VIOLET, "#F4F1FF"), (200, "#F4F1FF", VIOLET)):
        tile = rounded(render(mark_svg(col, s, 0.5, bg=bgc), s), 0.22)
        board.paste(tile, (x, y0 + 122), tile)
        x += s + 30
    for s in (64, 40, 24, 16):
        ic = rounded(render(mark_svg("#F4F1FF", s, 0.5, bg=VIOLET), s), 0.22)
        board.paste(ic, (x, y0 + 122 + 200 - s), ic)
        x += s + 20
    return board


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    wallpaper_panel("light").save(OUT / "icon-on-light-wallpaper.png")
    wallpaper_panel("dark").save(OUT / "icon-on-dark-wallpaper.png")
    small_sizes().save(OUT / "icon-small-sizes.png")
    splash_phones().save(OUT / "splash-phones.png")
    concept_board().save(BRAND_DOCS / "concept-board.png")
    print("previews written")
