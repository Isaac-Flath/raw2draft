#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow"]
# ///
"""Render carousel slides from social/carousel.md as 1080x1350 PNG images."""

import re
import sys
import textwrap
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

WIDTH = 1080
HEIGHT = 1350

BG_COLOR = (245, 243, 240)       # warm off-white
TEXT_COLOR = (35, 35, 35)         # near-black
TITLE_COLOR = (25, 25, 25)       # slightly darker for titles
ACCENT_COLOR = (180, 170, 158)   # muted warm gray for decorative elements
LINE_COLOR = (210, 205, 198)     # subtle divider

FONT_PATH = "/System/Library/Fonts/HelveticaNeue.ttc"


def load_fonts():
    try:
        title_font = ImageFont.truetype(FONT_PATH, 62, index=1)  # Bold
        body_font = ImageFont.truetype(FONT_PATH, 38, index=0)   # Regular
        number_font = ImageFont.truetype(FONT_PATH, 28, index=1)  # Bold small
    except (OSError, IndexError):
        title_font = ImageFont.truetype(FONT_PATH, 62)
        body_font = ImageFont.truetype(FONT_PATH, 38)
        number_font = ImageFont.truetype(FONT_PATH, 28)
    return title_font, body_font, number_font


def parse_carousel(text):
    """Parse carousel.md and return list of {title, lines} dicts."""
    match = re.search(r"Slides\s*\([^)]*\)\s*:\s*\n", text)
    if not match:
        print("Error: Could not find 'Slides (...):\\n' section in carousel.md")
        sys.exit(1)

    slides_text = text[match.end():]
    slides = []

    for line in slides_text.strip().splitlines():
        line = line.strip()
        if not line:
            continue
        # Match: N) Title -- body / body / body
        m = re.match(r"\d+\)\s*(.+?)\s*(?:--|—)\s*(.+)", line)
        if not m:
            continue
        title = m.group(1).strip()
        body_raw = m.group(2).strip()
        body_lines = [part.strip() for part in body_raw.split(" / ")]
        slides.append({"title": title, "lines": body_lines})

    return slides


def render_slide(slide, index, total_slides, title_font, body_font, number_font, out_dir):
    img = Image.new("RGB", (WIDTH, HEIGHT), BG_COLOR)
    draw = ImageDraw.Draw(img)

    margin_x = 100
    content_width = WIDTH - 2 * margin_x

    # Slide number indicator (dots at top)
    indicator_y = 90
    dot_spacing = 28
    dot_radius = 6
    total_dots_width = (total_slides - 1) * dot_spacing
    start_x = (WIDTH - total_dots_width) / 2
    for i in range(total_slides):
        cx = start_x + i * dot_spacing
        fill = TEXT_COLOR if i == index else ACCENT_COLOR
        draw.ellipse(
            [cx - dot_radius, indicator_y - dot_radius,
             cx + dot_radius, indicator_y + dot_radius],
            fill=fill,
        )

    # Title
    title_y = 220
    title_bbox = draw.textbbox((0, 0), slide["title"], font=title_font)
    title_w = title_bbox[2] - title_bbox[0]
    draw.text(
        ((WIDTH - title_w) / 2, title_y),
        slide["title"],
        fill=TITLE_COLOR,
        font=title_font,
    )

    # Divider line under title
    line_y = title_y + 90
    line_half = 60
    draw.line(
        [(WIDTH / 2 - line_half, line_y), (WIDTH / 2 + line_half, line_y)],
        fill=LINE_COLOR,
        width=2,
    )

    # Body lines
    body_start_y = line_y + 70
    line_spacing = 58

    # Wrap and collect all text lines for vertical centering
    all_text_lines = []
    for line_text in slide["lines"]:
        sub_lines = line_text.split("\n")
        for sub in sub_lines:
            wrapped = textwrap.wrap(sub, width=32)
            all_text_lines.extend(wrapped)
        all_text_lines.append("")  # gap between items

    if all_text_lines and all_text_lines[-1] == "":
        all_text_lines.pop()

    total_text_height = len(all_text_lines) * line_spacing
    available_space = HEIGHT - body_start_y - 120
    body_y = body_start_y + max(0, (available_space - total_text_height) / 2)

    current_y = body_y
    for line_text in slide["lines"]:
        sub_lines = line_text.split("\n")
        for sub in sub_lines:
            wrapped = textwrap.wrap(sub, width=32)
            for wline in wrapped:
                bbox = draw.textbbox((0, 0), wline, font=body_font)
                tw = bbox[2] - bbox[0]
                draw.text(
                    ((WIDTH - tw) / 2, current_y),
                    wline,
                    fill=TEXT_COLOR,
                    font=body_font,
                )
                current_y += line_spacing
        current_y += line_spacing * 0.6  # gap between items

    filename = f"carousel-{index + 1}.png"
    img.save(out_dir / filename, "PNG")
    print(f"  {filename}")


def main():
    if len(sys.argv) < 2:
        print("Usage: render.py <project-dir>")
        sys.exit(1)

    project_dir = Path(sys.argv[1])
    carousel_md = project_dir / "social" / "carousel.md"

    if not carousel_md.exists():
        print(f"Error: {carousel_md} not found")
        sys.exit(1)

    text = carousel_md.read_text()
    slides = parse_carousel(text)

    if not slides:
        print("Error: No slides parsed from carousel.md")
        sys.exit(1)

    out_dir = project_dir / "social"
    out_dir.mkdir(parents=True, exist_ok=True)

    title_font, body_font, number_font = load_fonts()

    print(f"Rendering {len(slides)} carousel slides...")
    for i, slide in enumerate(slides):
        render_slide(slide, i, len(slides), title_font, body_font, number_font, out_dir)
    print(f"Done. {len(slides)} slides saved to {out_dir}")


if __name__ == "__main__":
    main()
