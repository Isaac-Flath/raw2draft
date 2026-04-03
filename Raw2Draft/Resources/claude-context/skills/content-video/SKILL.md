---
name: content-video
description: Compose videos from project assets using Remotion
---

# Content Video

Create videos from project assets (source videos, images, screenshots, blog text) using Remotion.

## Prerequisites

- Node.js 18+ and npm
- ffprobe (from ffmpeg) for video duration detection
- Source video or images in the project

## Workflow

### 1. Setup Remotion Project

```bash
uv run .claude/skills/content-video/scripts/setup_remotion.py <project-dir>
```

This will:
- Discover assets: videos in `source/`, images in `images/` and `screenshots/`, blog in `content/`
- Create a `video/` subdirectory with Remotion project scaffolding
- Symlink project assets into `video/public/`
- Install npm dependencies
- Generate composition code from templates

### 2. Edit Composition (Optional)

After setup, edit `video/src/Composition.tsx` to adjust:
- Overlay timing and positioning
- Text content and animations
- Sequence ordering

Preview with: `cd video && npx remotion preview`

### 3. Render Final Video

```bash
uv run .claude/skills/content-video/scripts/render_video.py <project-dir>
```

Output: `video/out/final.mp4` (1920x1080, h264, 30fps)

## Templates

- `Root.tsx.jinja2` - Remotion Root component
- `Composition.tsx.jinja2` - Main composition with overlays
- `index.ts.jinja2` - Entry point

## Tips

- Run `/content-image` first to generate overlay images
- Run `/content-screenshot` to extract key frames from source video
- The composition template creates a base video layer with image/text overlays
