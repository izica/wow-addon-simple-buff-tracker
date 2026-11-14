"""Draw the CurseForge icon: media/curseforge_icon.png, 400x400.

An action bar slot (gold beveled frame, dark cell, the same family as the other
addons' icons) with a glowing green "buff" arrow inside a timer ring that is
running out -- a tracked buff and its time left -- and a blue "refresh" badge
in the corner: a click puts the buff back. Drawn at 4x and scaled down for
smooth edges. Needs Pillow.

    python scripts/make_icon.py
"""

import math
import os

from PIL import Image, ImageChops, ImageDraw, ImageFilter

REPOSITORY = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUTPUT = os.path.join(REPOSITORY, "media", "curseforge_icon.png")

SIZE = 400
SCALE = 4
CANVAS = SIZE * SCALE

GOLD_DARK = (92, 62, 18)
GOLD = (214, 168, 64)
GOLD_LIGHT = (255, 226, 140)
CELL_CENTER = (30, 70, 62)
CELL_EDGE = (6, 14, 14)
RING_TRACK = (255, 255, 255, 34)
RING = (255, 206, 84)
ARROW = (96, 236, 104)
ARROW_LIGHT = (214, 255, 200)
BADGE = (52, 142, 232)
BADGE_DARK = (14, 50, 104)
WHITE = (255, 255, 255)

RING_LEFT = 0.72   # the share of the timer still left


def radial_gradient(size, center_color, edge_color):
    gradient = Image.new("RGB", (size, size))
    pixels = gradient.load()
    middle = (size - 1) / 2
    longest = math.hypot(middle, middle)
    for y in range(size):
        for x in range(size):
            share = min(1.0, math.hypot(x - middle, y - middle * 0.85) / longest)
            share = share ** 1.4
            pixels[x, y] = tuple(
                round(center_color[channel] * (1 - share) + edge_color[channel] * share)
                for channel in range(3)
            )
    return gradient


def rounded_mask(size, box, radius):
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(box, radius=radius, fill=255)
    return mask


def glow(layer, radius):
    """The layer over two blurred copies of itself: a wide soft halo and a tight one."""
    wide = layer.filter(ImageFilter.GaussianBlur(radius * 1.6))
    tight = layer.filter(ImageFilter.GaussianBlur(radius * 0.6))
    halo = Image.alpha_composite(wide, wide)
    halo = Image.alpha_composite(halo, tight)
    return Image.alpha_composite(halo, layer)


def shadow_of(layer, radius):
    blurred = layer.filter(ImageFilter.GaussianBlur(radius))
    black = Image.new("RGB", blurred.size, (0, 0, 0))
    return Image.merge("RGBA", (*black.split(), blurred.getchannel("A")))


def draw_frame(icon):
    """Gold beveled frame: dark outer edge, gold body, light inner bevel."""
    draw = ImageDraw.Draw(icon)
    margin = 10 * SCALE
    radius = 46 * SCALE
    for step, color in enumerate((GOLD_DARK, GOLD, GOLD_LIGHT, GOLD, GOLD_DARK)):
        inset = margin + step * 7 * SCALE
        draw.rounded_rectangle(
            (inset, inset, CANVAS - inset, CANVAS - inset),
            radius=max(8, radius - step * 6 * SCALE),
            outline=color,
            width=8 * SCALE,
        )
    return margin + 5 * 7 * SCALE


def draw_cell(icon, inset):
    box = (inset, inset, CANVAS - inset, CANVAS - inset)
    cell_size = CANVAS - inset * 2
    cell = radial_gradient(cell_size // SCALE, CELL_CENTER, CELL_EDGE).resize((cell_size, cell_size), Image.BICUBIC)
    mask = rounded_mask(CANVAS, box, 22 * SCALE).crop(box)
    icon.paste(cell, box[:2], mask)

    # gloss: a soft light band across the top of the cell
    gloss = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    ImageDraw.Draw(gloss).ellipse(
        (inset - 120 * SCALE, inset - 260 * SCALE, CANVAS - inset + 60 * SCALE, inset + 120 * SCALE),
        fill=(255, 255, 255, 30),
    )
    cell_mask = rounded_mask(CANVAS, box, 22 * SCALE)
    gloss.putalpha(ImageChops.multiply(gloss.getchannel("A"), cell_mask))
    icon.alpha_composite(gloss)


def draw_timer_ring(icon):
    """A dim full track and a bright arc over the time left, from the top, clockwise, with a tick at its end."""
    center = CANVAS / 2 - 6 * SCALE
    ring = 112 * SCALE
    width = 15 * SCALE
    box = (center - ring, center - ring, center + ring, center + ring)

    track = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    ImageDraw.Draw(track).arc(box, start=0, end=360, fill=RING_TRACK, width=width)
    icon.alpha_composite(track)

    layer = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    start = -90
    end = start + 360 * RING_LEFT
    draw.arc(box, start=start, end=end, fill=RING, width=width)
    # round caps on both ends of the arc
    for angle in (start, end):
        radians = math.radians(angle)
        x = center + math.cos(radians) * (ring - width / 2)
        y = center + math.sin(radians) * (ring - width / 2)
        cap = width / 2
        draw.ellipse((x - cap, y - cap, x + cap, y + cap), fill=RING)
    icon.alpha_composite(glow(layer, 12 * SCALE))


def draw_arrow(icon):
    """The buff: a thick upward arrow, light at the top."""
    center_x = CANVAS / 2 - 6 * SCALE
    top = CANVAS / 2 - 82 * SCALE
    head_bottom = CANVAS / 2 - 2 * SCALE
    bottom = CANVAS / 2 + 74 * SCALE
    head_half = 66 * SCALE
    shaft_half = 26 * SCALE
    shape = [
        (center_x, top),
        (center_x + head_half, head_bottom),
        (center_x + shaft_half, head_bottom),
        (center_x + shaft_half, bottom),
        (center_x - shaft_half, bottom),
        (center_x - shaft_half, head_bottom),
        (center_x - head_half, head_bottom),
    ]

    mask = Image.new("L", (CANVAS, CANVAS), 0)
    ImageDraw.Draw(mask).polygon(shape, fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(2 * SCALE)).point(lambda value: 255 if value > 110 else 0)

    # vertical gradient: light at the tip, green at the bottom
    gradient = Image.new("RGBA", (CANVAS, CANVAS))
    pixels = ImageDraw.Draw(gradient)
    for y in range(int(top), int(bottom) + 1):
        share = (y - top) / (bottom - top)
        share = min(1.0, share * 1.6)
        color = tuple(round(ARROW_LIGHT[c] * (1 - share) + ARROW[c] * share) for c in range(3))
        pixels.line((0, y, CANVAS, y), fill=color + (255,))
    layer = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    layer.paste(gradient, (0, 0), mask)

    green = Image.new("RGBA", (CANVAS, CANVAS), ARROW + (0,))
    green.putalpha(mask)
    icon.alpha_composite(shadow_of(layer, 8 * SCALE))
    icon.alpha_composite(glow(green, 16 * SCALE))
    icon.alpha_composite(layer)


def draw_badge(icon):
    """A blue round badge with a white circular "refresh" arrow."""
    layer = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    radius = 54 * SCALE
    center_x = CANVAS - 92 * SCALE
    center_y = CANVAS - 92 * SCALE
    draw.ellipse(
        (center_x - radius - 7 * SCALE, center_y - radius - 7 * SCALE,
         center_x + radius + 7 * SCALE, center_y + radius + 7 * SCALE),
        fill=GOLD_DARK,
    )
    draw.ellipse((center_x - radius, center_y - radius, center_x + radius, center_y + radius), fill=BADGE_DARK)
    draw.ellipse(
        (center_x - radius + 6 * SCALE, center_y - radius + 6 * SCALE,
         center_x + radius - 6 * SCALE, center_y + radius - 2 * SCALE),
        fill=BADGE,
    )

    # the refresh arrow: an open circle and an arrowhead at its end, clockwise
    loop = 27 * SCALE
    width = 10 * SCALE
    start = -60
    end = 230
    draw.arc((center_x - loop, center_y - loop, center_x + loop, center_y + loop),
             start=start, end=end, fill=WHITE, width=width)
    tip_angle = math.radians(start)
    middle = loop - width / 2
    base_x = center_x + math.cos(tip_angle) * middle
    base_y = center_y + math.sin(tip_angle) * middle
    # the head points along the circle (clockwise is +angle on screen)
    along = (-math.sin(tip_angle), math.cos(tip_angle))
    outward = (math.cos(tip_angle), math.sin(tip_angle))
    head = 19 * SCALE
    tip = (base_x - along[0] * head, base_y - along[1] * head)
    side_a = (base_x + outward[0] * head * 0.85, base_y + outward[1] * head * 0.85)
    side_b = (base_x - outward[0] * head * 0.85, base_y - outward[1] * head * 0.85)
    draw.polygon([tip, side_a, side_b], fill=WHITE)

    icon.alpha_composite(shadow_of(layer, 10 * SCALE))
    icon.alpha_composite(layer)


def main():
    icon = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    inner_edge = draw_frame(icon)
    draw_cell(icon, inner_edge)
    draw_frame(icon)   # again, over the cell edge
    draw_timer_ring(icon)
    draw_arrow(icon)
    draw_badge(icon)

    os.makedirs(os.path.dirname(OUTPUT), exist_ok=True)
    icon.resize((SIZE, SIZE), Image.LANCZOS).save(OUTPUT)
    print(OUTPUT)


if __name__ == "__main__":
    main()
