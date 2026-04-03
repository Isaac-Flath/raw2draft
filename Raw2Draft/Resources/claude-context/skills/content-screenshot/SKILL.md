---
name: content-screenshot
description: Extract screenshots from video at specific timestamps. Use when you need specific frames from a video for blog posts or other content.
---

# /content-screenshot

Extract screenshots from video at specific timestamps.

## Usage

```
/content-screenshot <video_path> <timestamp1> [timestamp2] [timestamp3] ...
```

## Timestamp Formats

All formats supported:
- `1:30` or `01:30` (MM:SS)
- `1:30:45` (HH:MM:SS)
- `90` or `90s` (seconds)

## Working Directory

Content Conductor launches Claude from the project directory (`projects/<id>`). Paths below are relative to that directory.

## Run

```bash
# Single screenshot at 1 minute 30 seconds
VIDEO=$(ls source/*.mp4 2>/dev/null | head -1)
uv run .claude/skills/content-screenshot/scripts/screenshot.py "$VIDEO" screenshots 1:30

# Multiple screenshots
uv run .claude/skills/content-screenshot/scripts/screenshot.py "$VIDEO" screenshots 0:45 2:15 5:30 10:00
```

## Output

Screenshots saved to output directory with timestamp names:
- `screenshot-00m45s.png`
- `screenshot-02m15s.png`
- `screenshot-05m30s.png`

## Workflow

This skill is typically called by the blog generation process:

1. `/content-transcribe` creates transcript and chapters
2. While writing blog post, identify moments needing visuals
3. `/content-screenshot` extracts specific frames
4. Reference in blog: `![Description](screenshots/screenshot-02m15s.png)`
