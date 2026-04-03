---
name: video-overlays
description: Produce professional overlay cards for edited YouTube videos.
---

# Video Overlays Skill

Produce professional overlay cards for edited YouTube videos. Read the top-level `references/visual-editing-principles.md` before making any overlay decisions — it contains the mental model for what to overlay, where, how big, and why.

## Output Directory

**All outputs go in `<project_root>/claude-edits/`.**

```
<project_root>/claude-edits/
    <video_stem>_overlays.json      # Overlay specification with per-overlay Resolve properties
    overlays/
        assets/                     # Screenshots, thumbnails, logos (from gather_assets.py)
        rendered/                   # Text overlays rendered as PNG cards (via ffmpeg)
        frames/                     # Extracted video frames for visual analysis
```

## Tools

- `ffmpeg` — extract video frames, render text overlay cards
- `gather_assets.py` — fetch screenshots/OG images for URLs mentioned in the video (uses Playwright)

## Workflow

### Step 1: Identify what deserves an overlay

Read the transcript and decide what moments benefit from visual reinforcement. **Do not use a script for this — reason about the content.** Ask:
- What are the key takeaways the viewer should remember?
- Are there URLs, commands, or names that are hard to catch by ear?
- Where would a CTA (newsletter, subscribe) fit naturally? (Mid-roll 60-70%, outro — not intro)
- Is there content already visible on screen that does NOT need a redundant label?

### Step 2: Extract video frames at each overlay timestamp

```bash
ffmpeg -ss <seconds> -i <source_video> -frames:v 1 -update 1 -vf scale=960:-1 \
    <project_root>/claude-edits/overlays/frames/<overlay_id>_frame.png
```

### Step 3: Look at each frame and decide placement

Read each frame image. For each overlay, decide:
1. Where is the face/webcam? Where is the content? Where is dead space?
2. Set exact Resolve Pan/Tilt/ZoomX/ZoomY values for this specific frame
3. Composite-preview the overlay onto the frame to verify it looks right before building in Resolve

```bash
# Preview composite (scale values to match preview resolution)
ffmpeg -y -i frame.png -i overlay.png \
    -filter_complex "[1]scale=<preview_width>:-1[card];[0][card]overlay=x=<px>:y=<py>" \
    -frames:v 1 -update 1 preview.png
```

If the preview shows the overlay blocking content or covering the face, adjust and re-preview.

### Step 4: Gather image assets (for URL/blog/tool mentions)

```bash
cd <project_root>/.claude/skills/video-overlays
uv run scripts/gather_assets.py <project_root>/claude-edits/<stem>_mentions.json --output-dir <project_root>/claude-edits/
```

### Step 5: Render text overlay cards

```bash
ffmpeg -y -f lavfi -i "color=c=0x0d1117@0.88:s=1600x80:d=1,format=rgba" \
    -vf "drawbox=x=0:y=0:w=8:h=80:c=0x58a6ff@1.0:t=fill,drawtext=text='<label>':fontfile=/System/Library/Fonts/Helvetica.ttc:fontsize=38:fontcolor=0xffffff:x=28:y=(h-text_h)/2" \
    -frames:v 1 -update 1 rendered/<overlay_id>.png
```

These are starting-point defaults for card style. Adjust colors, size, font based on the video's visual context. Dark backgrounds need lighter cards; light backgrounds need darker or more opaque cards.

### Step 6: Write the overlay spec

Each overlay gets a `resolve` dict with exact pixel values and a `_note` explaining the placement reasoning:

```json
{
  "id": "overlay_justfile_key",
  "type": "key-takeaway",
  "label": "One Just file = entry point for all commands",
  "timing": { "source_start": 51.3, "source_end": 59.1, "display_duration": 7.8 },
  "resolve": {
    "ZoomX": 0.55, "ZoomY": 0.55,
    "Pan": -200, "Tilt": -930,
    "_note": "VS Code with code and terminal. Lower-third on terminal tab bar, left of webcam bottom-right."
  }
}
```

## Resolve Coordinate Reference (3840x2160)

- **Pan**: pixels from center. +right, -left. Range ~-1920 to 1920.
- **Tilt**: pixels from center. +up, -down. Range ~-1080 to 1080.
- **ZoomX/ZoomY**: scale. 1.0 = native. A 1600px card at 0.5 = 800px displayed on 3840px canvas.

## File Structure
```
scripts/
    gather_assets.py         # Fetch screenshots, OG images (Playwright + requests)
```
