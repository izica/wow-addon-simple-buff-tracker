"""Draw the CurseForge icon, 400x400, and the minimap button's texture.

    python scripts/make_icon.py              -- media/curseforge_icon.png (swipe) and
                                                SimpleBuffTracker/media/icon.tga (its picture
                                                without the frame, 64x64: the minimap button
                                                and the icon in the addon list)
    python scripts/make_icon.py variants     -- every concept into media/icon_variants/ to compare

Also SimpleBuffTracker/media/lock_open.tga, 32x32: a gold open padlock -- the anchor
the unlocked panel shows (drawn here: no game texture of it is sure to be on the client).

Concepts:
  swipe      -- (the chosen one) a glowing arcane buff icon with the game's dark cooldown swipe
                over the time already gone, in a dark metal frame;
  hourglass  -- a gold hourglass with glowing green sand in a round emblem;
  grid       -- a little buff panel: three lit buffs and one missing (grey, red glow).

Drawn at 4x and scaled down for smooth edges. Needs Pillow and numpy.
"""

import math
import os
import sys

import numpy
from PIL import Image, ImageChops, ImageDraw, ImageFilter

REPOSITORY = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MEDIA = os.path.join(REPOSITORY, "media")

SIZE = 400
SCALE = 4
CANVAS = SIZE * SCALE
MIDDLE = CANVAS / 2


# ---------------------------------------------------------------- helpers

def layer():
    return Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))


def glow(source, radius, strength=2):
    """Soft halos of the layer under it."""
    result = layer()
    for _ in range(strength):
        result = Image.alpha_composite(result, source.filter(ImageFilter.GaussianBlur(radius * 1.6)))
    result = Image.alpha_composite(result, source.filter(ImageFilter.GaussianBlur(radius * 0.6)))
    return Image.alpha_composite(result, source)


def shadow_of(source, radius, opacity=1.0):
    blurred = source.filter(ImageFilter.GaussianBlur(radius))
    alpha = blurred.getchannel("A").point(lambda value: round(value * opacity))
    black = Image.new("RGB", blurred.size, (0, 0, 0))
    return Image.merge("RGBA", (*black.split(), alpha))


def distance_map(center_x, center_y, size=CANVAS):
    y, x = numpy.mgrid[0:size, 0:size].astype(numpy.float32)
    return numpy.hypot(x - center_x, y - center_y), x, y


def radial(colors, center=(MIDDLE, MIDDLE), radius=CANVAS * 0.7, power=1.0):
    """colors: [(stop 0..1, (r, g, b)), ...] from the center out."""
    distance, _, _ = distance_map(*center)
    share = numpy.clip(distance / radius, 0, 1) ** power
    image = numpy.zeros((CANVAS, CANVAS, 4), numpy.float32)
    image[..., 3] = 255
    stops = [stop for stop, _ in colors]
    for channel in range(3):
        values = [color[channel] for _, color in colors]
        image[..., channel] = numpy.interp(share, stops, values)
    return Image.fromarray(image.astype(numpy.uint8))


def rays(count, color, alpha, center=(MIDDLE, MIDDLE), width_share=0.5):
    """Light rays around a center: alternating soft wedges."""
    distance, x, y = distance_map(*center)
    angle = numpy.arctan2(y - center[1], x - center[0])
    wave = (numpy.cos(angle * count) + 1) / 2
    wave = numpy.clip((wave - (1 - width_share)) / width_share, 0, 1)
    fade = numpy.clip(1 - distance / (CANVAS * 0.75), 0, 1)
    image = numpy.zeros((CANVAS, CANVAS, 4), numpy.float32)
    image[..., 0], image[..., 1], image[..., 2] = color
    image[..., 3] = wave * fade * alpha
    return Image.fromarray(image.astype(numpy.uint8))


def masked(image, mask):
    result = image.copy()
    result.putalpha(ImageChops.multiply(image.getchannel("A"), mask))
    return result


def rounded_mask(box, radius):
    mask = Image.new("L", (CANVAS, CANVAS), 0)
    ImageDraw.Draw(mask).rounded_rectangle(box, radius=radius, fill=255)
    return mask


def circle_mask(center, radius):
    mask = Image.new("L", (CANVAS, CANVAS), 0)
    x, y = center
    ImageDraw.Draw(mask).ellipse((x - radius, y - radius, x + radius, y + radius), fill=255)
    return mask


def star(center, long_ray, short_ray, thin, rotation=0):
    """A 4-point sparkle: two long and two short points."""
    x, y = center
    points = []
    for index in range(8):
        angle = math.radians(rotation + index * 45 - 90)
        if index % 2 == 1:
            reach = thin
        elif index % 4 == 0:
            reach = long_ray
        else:
            reach = short_ray
        points.append((x + math.cos(angle) * reach, y + math.sin(angle) * reach))
    return points


def sparkle(target, center, size, color=(255, 255, 255), glow_radius=None):
    spark = layer()
    ImageDraw.Draw(spark).polygon(star(center, size, size, size * 0.16), fill=color + (255,))
    target.alpha_composite(glow(spark, glow_radius or size * 0.35, 1))


def metal_frame(icon, box, radius, thickness):
    """A dark beveled metal frame: dark edge, steel body, light inner line."""
    draw = ImageDraw.Draw(icon)
    left, top, right, bottom = box
    steps = [(12, 12, 16), (88, 92, 104), (150, 156, 170), (70, 74, 86), (18, 18, 24)]
    band = thickness / len(steps)
    for step, color in enumerate(steps):
        inset = step * band
        draw.rounded_rectangle(
            (left + inset, top + inset, right - inset, bottom - inset),
            radius=max(4, radius - inset), outline=color, width=math.ceil(band) + 2,
        )


# ---------------------------------------------------------------- swipe

def swipe_art():
    """The picture inside the frame, full square: also the minimap button's texture."""
    art = radial([(0, (120, 200, 255)), (0.25, (60, 90, 220)), (0.6, (40, 20, 110)), (1, (8, 4, 30))],
                 center=(MIDDLE, MIDDLE * 0.95), radius=CANVAS * 0.62)
    art.alpha_composite(rays(12, (170, 220, 255), 70, center=(MIDDLE, MIDDLE * 0.95)))

    # arcane swirl: arcs around the middle
    swirl = layer()
    draw = ImageDraw.Draw(swirl)
    for radius, start, length, width, color in (
        (300, 200, 150, 22, (150, 120, 255)),
        (360, 20, 140, 16, (120, 220, 255)),
        (240, 80, 120, 14, (220, 160, 255)),
        (420, 250, 100, 12, (100, 180, 255)),
    ):
        r = radius * SCALE / 4 * 2
        draw.arc((MIDDLE - r, MIDDLE - r, MIDDLE + r, MIDDLE + r), start=start, end=start + length,
                 fill=color + (220,), width=width * SCALE // 2)
    art.alpha_composite(glow(swirl, 10 * SCALE))

    # the buff: a big sparkle
    spark = layer()
    ImageDraw.Draw(spark).polygon(star((MIDDLE, MIDDLE * 0.95), 300, 210, 46), fill=(255, 250, 225, 255))
    art.alpha_composite(glow(spark, 40 * SCALE // 4 * 2, 3))
    sparkle(art, (MIDDLE + 330, MIDDLE - 330), 70)
    sparkle(art, (MIDDLE - 360, MIDDLE + 250), 50)

    # the cooldown swipe: the time gone darkened, clockwise from the top
    gone = 0.33
    swipe = layer()
    reach = CANVAS
    start = -90
    end = start + 360 * gone
    ImageDraw.Draw(swipe).pieslice((MIDDLE - reach, MIDDLE - reach, MIDDLE + reach, MIDDLE + reach),
                                   start=start, end=end, fill=(0, 0, 0, 200))
    art.alpha_composite(swipe)
    # the bright edge of the swipe
    edge = layer()
    angle = math.radians(end)
    far = CANVAS * 0.8
    near = CANVAS * 0.12
    ImageDraw.Draw(edge).line((MIDDLE + math.cos(angle) * near, MIDDLE + math.sin(angle) * near,
                               MIDDLE + math.cos(angle) * far, MIDDLE + math.sin(angle) * far),
                              fill=(255, 230, 150, 200), width=3 * SCALE)
    art.alpha_composite(glow(edge, 8 * SCALE))
    return art


def concept_swipe():
    icon = layer()
    margin = 14 * SCALE
    box = (margin, margin, CANVAS - margin, CANVAS - margin)
    frame_width = 26 * SCALE
    cell_box = tuple(value + frame_width * sign for value, sign in zip(box, (1, 1, -1, -1)))
    cell_mask = rounded_mask(cell_box, 30 * SCALE)
    art = swipe_art()

    icon.alpha_composite(shadow_of(masked(Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 255)),
                                          rounded_mask(box, 44 * SCALE)), 8 * SCALE, 0.7))
    icon.alpha_composite(masked(art, cell_mask))
    # gloss over the top
    gloss = layer()
    ImageDraw.Draw(gloss).ellipse((cell_box[0] - 500, cell_box[1] - 1100, cell_box[2] + 300, cell_box[1] + 420),
                                  fill=(255, 255, 255, 30))
    icon.alpha_composite(masked(gloss, cell_mask))
    metal_frame(icon, box, 44 * SCALE, frame_width)
    return icon


# ---------------------------------------------------------------- hourglass

def concept_hourglass():
    icon = layer()
    center = (MIDDLE, MIDDLE)
    outer = MIDDLE - 12 * SCALE
    inner = outer - 30 * SCALE

    # gold ring
    ring = radial([(0, (255, 236, 160)), (0.5, (214, 160, 56)), (1, (110, 70, 20))],
                  center=(MIDDLE * 0.7, MIDDLE * 0.5), radius=CANVAS)
    icon.alpha_composite(shadow_of(masked(ring, circle_mask(center, outer)), 8 * SCALE, 0.8))
    icon.alpha_composite(masked(ring, circle_mask(center, outer)))
    ImageDraw.Draw(icon).ellipse((MIDDLE - outer, MIDDLE - outer, MIDDLE + outer, MIDDLE + outer),
                                 outline=(70, 40, 10, 255), width=4 * SCALE)

    # the night inside, with rays
    art = radial([(0, (60, 150, 110)), (0.35, (30, 60, 90)), (0.75, (16, 18, 48)), (1, (6, 6, 20))],
                 radius=inner * 1.05)
    art.alpha_composite(rays(16, (180, 255, 200), 55))
    for x, y, size in ((-470, -330, 40), (430, -420, 30), (500, 260, 46), (-430, 380, 30), (-200, -560, 22)):
        sparkle(art, (MIDDLE + x, MIDDLE + y), size)

    # the hourglass
    glass = layer()
    draw = ImageDraw.Draw(glass)
    top = MIDDLE - 470
    bottom = MIDDLE + 470
    half = 300          # half the width of a bulb
    neck = 34
    def bulb(y_wide, y_neck):
        points = []
        for step in range(41):
            share = step / 40
            y = y_wide + (y_neck - y_wide) * share
            width = neck + (half - neck) * math.cos(share * math.pi / 2) ** 1.3
            points.append((MIDDLE + width, y))
        return points
    upper = bulb(top + 70, MIDDLE)
    lower = bulb(bottom - 70, MIDDLE)
    outline = upper + list(reversed(lower))
    outline += [(2 * MIDDLE - x, y) for x, y in reversed(outline)]
    draw.polygon(outline, fill=(170, 230, 255, 60))

    # sand: the rest in the top bulb, a pile below, a stream between
    sand_mask = Image.new("L", (CANVAS, CANVAS), 0)
    sand_draw = ImageDraw.Draw(sand_mask)
    sand_top = MIDDLE - 190
    upper_sand = [(x, y) for x, y in upper if y >= sand_top]
    upper_sand_full = [(MIDDLE + (upper_sand[0][0] - MIDDLE), sand_top)] + upper_sand
    upper_sand_full += [(2 * MIDDLE - x, y) for x, y in reversed(upper_sand_full)]
    sand_draw.polygon(upper_sand_full, fill=255)
    pile_top = MIDDLE + 230
    sand_draw.polygon([(MIDDLE - 250, bottom - 80), (MIDDLE, pile_top), (MIDDLE + 250, bottom - 80)], fill=255)
    lower_mask = Image.new("L", (CANVAS, CANVAS), 0)
    ImageDraw.Draw(lower_mask).polygon(outline, fill=255)
    sand_mask = ImageChops.multiply(sand_mask, lower_mask)
    sand_draw = ImageDraw.Draw(sand_mask)
    sand_draw.line((MIDDLE, MIDDLE - 20, MIDDLE, pile_top + 20), fill=255, width=14)
    sand_color = radial([(0, (230, 255, 200)), (0.5, (120, 240, 120)), (1, (40, 160, 70))],
                        center=(MIDDLE, MIDDLE), radius=600)
    sand = masked(sand_color, sand_mask)
    glass.alpha_composite(glow(sand, 14 * SCALE))

    # glass edge and the light on it
    draw = ImageDraw.Draw(glass)
    draw.line(outline + [outline[0]], fill=(220, 245, 255, 200), width=12, joint="curve")
    draw.line([(x - 70, y) for x, y in upper[5:30]], fill=(255, 255, 255, 120), width=16)

    # gold caps and posts
    cap = layer()
    cap_draw = ImageDraw.Draw(cap)
    for y in (top, bottom):
        cap_draw.rounded_rectangle((MIDDLE - 400, y - 50, MIDDLE + 400, y + 50), radius=30, fill=(214, 164, 60, 255))
        cap_draw.rounded_rectangle((MIDDLE - 400, y - 50, MIDDLE + 400, y - 10), radius=20, fill=(255, 226, 140, 255))
    for x in (MIDDLE - 350, MIDDLE + 350):
        cap_draw.rounded_rectangle((x - 22, top, x + 22, bottom), radius=20, fill=(190, 140, 50, 255))
        cap_draw.rounded_rectangle((x - 22, top, x - 6, bottom), radius=8, fill=(255, 226, 140, 255))

    art.alpha_composite(shadow_of(cap, 12 * SCALE, 0.8))
    art.alpha_composite(glass)
    art.alpha_composite(cap)
    icon.alpha_composite(masked(art, circle_mask(center, inner)))
    ImageDraw.Draw(icon).ellipse((MIDDLE - inner, MIDDLE - inner, MIDDLE + inner, MIDDLE + inner),
                                 outline=(255, 236, 170, 255), width=3 * SCALE)
    return icon


# ---------------------------------------------------------------- grid

def mini_icon(icon, box, colors, glyph, is_missing=False, swipe=None):
    left, top, right, bottom = box
    size = right - left
    cell_mask = rounded_mask(box, 18 * SCALE)
    art = radial(colors, center=((left + right) / 2, top + size * 0.45), radius=size * 0.8)
    art.alpha_composite(rays(10, (255, 255, 255), 40, center=((left + right) / 2, top + size * 0.45)))
    if not is_missing:
        picture = layer()
        glyph(ImageDraw.Draw(picture), (left + right) / 2, (top + bottom) / 2, size)
        art.alpha_composite(glow(picture, 10 * SCALE, 1))
    if swipe:
        cover = layer()
        cx, cy = (left + right) / 2, (top + bottom) / 2
        ImageDraw.Draw(cover).pieslice((cx - size, cy - size, cx + size, cy + size),
                                       start=-90, end=-90 + 360 * swipe, fill=(0, 0, 0, 160))
        art.alpha_composite(cover)
    if is_missing:
        grey = art.convert("L").point(lambda value: value * 0.55).convert("RGBA")
        art = grey
    shape = masked(art, cell_mask)
    if is_missing:
        red = layer()
        ImageDraw.Draw(red).rounded_rectangle(box, radius=18 * SCALE, outline=(255, 40, 30, 255), width=9 * SCALE)
        icon.alpha_composite(glow(red, 14 * SCALE, 3))
    icon.alpha_composite(shadow_of(shape, 6 * SCALE, 0.9))
    icon.alpha_composite(shape)
    border = (255, 60, 50) if is_missing else (16, 16, 20)
    ImageDraw.Draw(icon).rounded_rectangle(box, radius=18 * SCALE, outline=border + (255,), width=5 * SCALE)
    if is_missing:
        # "!" in the middle
        draw = ImageDraw.Draw(icon)
        cx, cy = (left + right) / 2, (top + bottom) / 2
        width = size * 0.11
        draw.rounded_rectangle((cx - width, cy - size * 0.3, cx + width, cy + size * 0.1),
                               radius=width, fill=(255, 220, 210, 255))
        draw.ellipse((cx - width, cy + size * 0.18, cx + width, cy + size * 0.18 + width * 2),
                     fill=(255, 220, 210, 255))


def glyph_arrow(draw, x, y, size):
    s = size * 0.3
    draw.polygon([(x, y - s), (x + s, y), (x + s * 0.4, y), (x + s * 0.4, y + s),
                  (x - s * 0.4, y + s), (x - s * 0.4, y), (x - s, y)], fill=(230, 255, 220, 255))


def glyph_star(draw, x, y, size):
    draw.polygon(star((x, y), size * 0.36, size * 0.26, size * 0.06), fill=(255, 250, 220, 255))


def glyph_shield(draw, x, y, size):
    s = size * 0.3
    top = y - s * 1.05
    points = [(x - s, top), (x, top - s * 0.18), (x + s, top), (x + s, y)]
    for step in range(1, 21):
        share = step / 20
        points.append((x + s * (1 - share) ** 1.2, y + s * 1.15 * math.sin(share * math.pi / 2)))
    points += [(2 * x - px, py) for px, py in reversed(points[3:])]
    draw.polygon(points, fill=(220, 240, 255, 255))


def glyph_flame(draw, x, y, size):
    s = size * 0.32
    points = []
    for step in range(60):
        t = step / 60 * 2 * math.pi
        radius = s * (0.62 + 0.38 * math.sin(t / 2) ** 6)
        px = x + math.sin(t) * radius * 0.8
        py = y + s * 0.25 - math.cos(t) * radius * 1.1 - (s * 0.35 if abs(math.sin(t / 2)) < 0.2 else 0)
        points.append((px, py))
    draw.polygon(star((x, y + s * 0.1), s * 1.1, s * 0.75, s * 0.32), fill=(255, 240, 200, 255))


def concept_grid():
    icon = layer()
    margin = 14 * SCALE
    box = (margin, margin, CANVAS - margin, CANVAS - margin)
    background = radial([(0, (52, 44, 34)), (1, (14, 12, 10))], radius=CANVAS * 0.75)
    plate_mask = rounded_mask(box, 44 * SCALE)
    icon.alpha_composite(shadow_of(masked(background, plate_mask), 8 * SCALE, 0.7))
    icon.alpha_composite(masked(background, plate_mask))
    metal_frame(icon, box, 44 * SCALE, 20 * SCALE)

    gap = 22 * SCALE
    inset = 50 * SCALE
    cell = (CANVAS - inset * 2 - gap) / 2
    places = [(inset, inset), (inset + cell + gap, inset), (inset, inset + cell + gap),
              (inset + cell + gap, inset + cell + gap)]
    styles = [
        ([(0, (190, 255, 160)), (0.5, (50, 170, 60)), (1, (10, 50, 20))], glyph_arrow, False, None),
        ([(0, (190, 220, 255)), (0.5, (50, 100, 220)), (1, (10, 20, 70))], glyph_shield, False, 0.3),
        ([(0, (255, 220, 150)), (0.5, (220, 110, 30)), (1, (70, 20, 5))], glyph_flame, False, None),
        ([(0, (230, 190, 255)), (0.5, (130, 60, 220)), (1, (30, 10, 70))], glyph_star, True, None),
    ]
    for (x, y), (colors, glyph, is_missing, swipe) in zip(places, styles):
        mini_icon(icon, (x, y, x + cell, y + cell), colors, glyph, is_missing, swipe)
    return icon


CONCEPTS = {
    "swipe": concept_swipe,
    "hourglass": concept_hourglass,
    "grid": concept_grid,
}


def render(name):
    return CONCEPTS[name]().resize((SIZE, SIZE), Image.LANCZOS)


LOCK_SIZE = 32
LOCK_OUTPUT = os.path.join(REPOSITORY, "SimpleBuffTracker", "media", "lock_open.tga")


def draw_open_lock():
    """A gold open padlock with a dark outline: the body, the shackle up and open on the right."""
    canvas = LOCK_SIZE * SCALE
    unit = canvas / 128            # drawn on a 128 grid
    image = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    outline = (20, 12, 2, 255)
    gold_dark = (176, 120, 30, 255)
    gold = (255, 206, 72, 255)
    gold_light = (255, 240, 170, 255)

    def box(left, top, right, bottom):
        return (left * unit, top * unit, right * unit, bottom * unit)

    # the shackle: a half ring on top, the left leg into the body, the right one lifted
    for width, color in ((20, outline), (12, gold_dark), (6, gold)):
        draw.arc(box(30, 10, 82, 62), start=180, end=360, fill=color, width=round(width * unit))
        leg = width / 2
        draw.rectangle(box(36 - leg, 36, 36 + leg, 70), fill=color)
        draw.rectangle(box(76 - leg, 36, 76 + leg, 46), fill=color)
    # the body
    draw.rounded_rectangle(box(18, 58, 110, 122), radius=14 * unit, fill=outline)
    draw.rounded_rectangle(box(24, 64, 104, 116), radius=10 * unit, fill=gold_dark)
    draw.rounded_rectangle(box(24, 64, 104, 104), radius=10 * unit, fill=gold)
    draw.rounded_rectangle(box(30, 68, 98, 78), radius=5 * unit, fill=gold_light)
    # the keyhole
    draw.ellipse(box(56, 80, 72, 96), fill=outline)
    draw.polygon([(60 * unit, 90 * unit), (68 * unit, 90 * unit), (70 * unit, 108 * unit), (58 * unit, 108 * unit)],
                 fill=outline)
    return image.resize((LOCK_SIZE, LOCK_SIZE), Image.LANCZOS)


CHOSEN = "swipe"
MINIMAP_SIZE = 64
MINIMAP_OUTPUT = os.path.join(REPOSITORY, "SimpleBuffTracker", "media", "icon.tga")


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "variants":
        folder = os.path.join(MEDIA, "icon_variants")
        os.makedirs(folder, exist_ok=True)
        for name in CONCEPTS:
            output = os.path.join(folder, name + ".png")
            render(name).save(output)
            print(output)
        return
    output = os.path.join(MEDIA, "curseforge_icon.png")
    render(CHOSEN).save(output)
    print(output)
    # the game reads uncompressed 32-bit TGA with a power-of-two size
    os.makedirs(os.path.dirname(MINIMAP_OUTPUT), exist_ok=True)
    minimap = swipe_art().resize((MINIMAP_SIZE, MINIMAP_SIZE), Image.LANCZOS)
    minimap.save(MINIMAP_OUTPUT, compression=None)
    print(MINIMAP_OUTPUT)
    draw_open_lock().save(LOCK_OUTPUT, compression=None)
    print(LOCK_OUTPUT)


if __name__ == "__main__":
    main()
