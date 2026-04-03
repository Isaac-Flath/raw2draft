---
name: content-carousel-render
description: Render carousel slides from social/carousel.md into 1080x1350 PNG images.
---

# /content-carousel-render

Render carousel slide PNGs from a project's `social/carousel.md` file.

## Usage

```
/content-carousel-render
```

## Prerequisite

Requires `social/carousel.md`. If missing, run `/content-social carousel` first.

## How It Works

1. Reads `social/carousel.md` from the active project
2. Finds the `Slides (...):\n` section
3. Parses each numbered line: `N) Title -- body line / body line / ...`
4. Renders each slide as a 1080x1350 PNG with warm off-white background, centered title, dot indicators, and wrapped body text
5. Saves to `social/carousel-1.png`, `social/carousel-2.png`, etc.

## Run

```bash
uv run .claude/skills/content-carousel-render/scripts/render.py <project-dir>
```

Example:

```bash
uv run .claude/skills/content-carousel-render/scripts/render.py projects/2026_02_21_japan
```

## Output

| File | Description |
|------|-------------|
| `social/carousel-N.png` | 1080x1350 slide image |

## See Also

- `/content-social carousel` - Generate the carousel.md source file
