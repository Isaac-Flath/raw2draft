# DaVinci Resolve API — Practical Notes

Tested against DaVinci Resolve Studio 20.3.2 on macOS. See resolve_scripting_api.txt for full API reference.

## Connection Boilerplate

```python
import sys
sys.path.insert(0, "/Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/Scripting/Modules")
import DaVinciResolveScript as dvr

resolve = dvr.scriptapp("Resolve")
pm = resolve.GetProjectManager()
resolve.OpenPage("edit")
```

The process name is `Resolve` (not `DaVinci Resolve`) for pgrep checks.

## Project + Timeline Creation

```python
project = pm.CreateProject("My Project")
project.SetSetting("timelineFrameRate", "30")
project.SetSetting("timelineResolutionWidth", "3840")
project.SetSetting("timelineResolutionHeight", "2160")

media_pool = project.GetMediaPool()
items = media_pool.ImportMedia(["/absolute/path/to/video.mp4"])
source = items[0]

timeline = media_pool.CreateEmptyTimeline("My Timeline")
project.SetCurrentTimeline(timeline)
```

## Appending Subclips (Track 1)

```python
media_pool.AppendToTimeline([{
    "mediaPoolItem": source,
    "startFrame": 180,   # source frame (not seconds)
    "endFrame": 330,
}])
```

**CRITICAL**: Do NOT include `"mediaType": 1` — that means VIDEO ONLY (no audio). To get both video AND audio, **omit the mediaType key entirely**.

Frames are source-file frames. At 30fps: seconds * 30 = frame number.

## Placing Overlays on Higher Tracks (No Gaps)

This is the correct way to place images/overlays on track 2+ without disrupting the video on track 1.

**CRITICAL**: `recordFrame` must include the timeline start offset. Timelines default to `01:00:00:00` which is frame 108000 at 30fps.

```python
# Add overlay track
timeline.AddTrack("video")  # creates track 2

# Get the timeline start frame offset
t1_items = timeline.GetItemListInTrack("video", 1)
tl_start_frame = t1_items[0].GetStart()  # 108000 for 01:00:00:00 at 30fps

# Import image
img_items = media_pool.ImportMedia(["/path/to/overlay.png"])

# Place on track 2 at 3 seconds into the timeline, lasting 2 seconds
offset_frames = int(3.0 * 30)  # 3 seconds at 30fps = 90 frames
dur_frames = int(2.0 * 30)     # 2 seconds = 60 frames

result = media_pool.AppendToTimeline([{
    "mediaPoolItem": img_items[0],
    "startFrame": 0,
    "endFrame": dur_frames,
    "trackIndex": 2,
    "recordFrame": tl_start_frame + offset_frames,  # MUST add offset!
    "mediaType": 1,  # video only (correct for images)
}])

# Set position/scale
item = result[0]
item.SetProperty("ZoomX", 0.3)                    # 30% of native size
item.SetProperty("ZoomY", 0.3)
item.SetProperty("Pan", float(width) * 0.3)       # pixels right of center
item.SetProperty("Tilt", float(-height) * 0.3)    # pixels below center
```

**If you use `recordFrame` without the start offset, the overlay will create gaps in track 1.**

### Rendering text as PNG for overlays

Text+ titles via `InsertFusionTitleIntoTimeline` are unreliable for positioning (always insert at playhead, hard to control which track). Instead, render text as PNG via ffmpeg and place as image overlay:

```bash
ffmpeg -y -f lavfi -i "color=c=0x222222@0.85:s=900x100:d=1,format=rgba" \
  -vf "drawtext=text='My Label':fontfile=/System/Library/Fonts/Helvetica.ttc:fontsize=42:fontcolor=white:x=(w-text_w)/2:y=(h-text_h)/2" \
  -frames:v 1 -update 1 overlay.png
```

### ffmpeg drawtext escaping gotchas

**Apostrophes** are the biggest pain point. The drawtext filter uses single quotes for its text value, so apostrophes must be escaped with a shell-level trick:

```bash
# To render: don't
# Use shell quote-break: '...don'\''t...'
-vf "drawtext=...text='Personal tools don\\'\''t need library abstractions'"
```

**Unicode characters (em dashes, etc.) do NOT work** with hex escaping in drawtext. `\xe2\x80\x94` renders literally as "xe2x80x94". Use ASCII alternatives instead:
- Em dash → regular hyphen with spaces: ` - `
- Smart quotes → straight quotes

**The `-update 1` flag is required** when writing a single frame to a named output file (not a sequence pattern like `%03d.png`). Without it, ffmpeg warns and may not write the file.

**Filter-complex escaping** differs from `-vf` escaping. In filter_complex, colons within drawtext must be escaped with backslashes: `\:text=` not `:text=`.

Then place using the image overlay method above. This gives exact control over position and timing.

## Timeline Markers

```python
# frameId is relative to timeline start (frame 0 = first frame of content)
timeline.AddMarker(0, "Blue", "Chapter 1: Intro", "optional note", 1)
timeline.AddMarker(150, "Green", "Chapter 2: Topic", "", 1)

# Verify
markers = timeline.GetMarkers()  # {frameId: {color, duration, note, name, customData}}
```

## Deleting a Project

```python
# Must close and switch to a different project first
pm.CloseProject(project)
pm.CreateProject("_temp")
pm.DeleteProject("My Project")
pm.CloseProject(pm.GetCurrentProject())
pm.DeleteProject("_temp")
```

## Timeline Item Properties (SetProperty/GetProperty)

Key properties for transforms:
- `Pan`: float, pixels from center (-4*width to 4*width), positive = right
- `Tilt`: float, pixels from center (-4*height to 4*height), positive = up (negative = down)
- `ZoomX`, `ZoomY`: float, 0.0 to 100.0 (1.0 = native size, 0.3 = 30%)
- `RotationAngle`: float, -360 to 360
- `CropLeft/Right/Top/Bottom`: float, pixels
- `CompositeMode`: int (0 = Normal)
- `FlipX`, `FlipY`: bool

### Overlay Positioning — Hard-Earned Lessons

**ZoomX behavior for overlay images is unintuitive.** Despite the docs saying `1.0 = native size`, overlay images placed on a 3840x2160 timeline behave as if their coordinate space is much larger than native pixels. The effective displayed size is much bigger than expected.

**Calibrated values for text overlay PNGs on a 3840x2160 timeline (rendered to 1920x1080):**

| Overlay image width | ZoomX/Y | Approx. frame coverage |
|---|---|---|
| 1300-1400px | 1.3 | ~47% of frame |
| 1500px | 1.2 | ~47% of frame |
| 2600px | 0.8 | ~54% of frame |

**Pan calibration (on 3840x2160 timeline):**
- `Pan=0` does NOT center the overlay — it appears shifted left, with text clipped off the left edge
- `Pan=500-700` is needed to left-align an overlay with a comfortable left margin
- Higher Pan values push the overlay further right
- For a 1400px overlay at ZoomX=1.3, `Pan=650` gives a good left-aligned position with margin

**Tilt calibration:**
- `Tilt=-420` places overlays roughly in the middle-lower area — this often overlaps a webcam PiP
- `Tilt=-700` moves overlays into the lower quarter but may still clip a bottom-right webcam
- `Tilt=-850` places overlays at the very bottom of the frame, below a typical webcam PiP
- For screens with a webcam in the bottom-right, use `Tilt=-800` to `-900` to clear it

**Always render and screenshot to verify.** Coordinate math alone is unreliable for this API. The render→screenshot→review loop is essential. Use a short test render (MarkIn/MarkOut around one overlay) to iterate quickly before doing full renders.

**Common mistakes:**
- Setting `Pan=-960` (half of 1920) thinking it will left-align — this pushes the overlay far off-screen
- Using ZoomX values >1.5 for narrow images — they become enormous and clip
- Not accounting for webcam PiP when setting Tilt — always check frames with the speaker visible

## Image Overlays (Website Cards, Screenshots, Logos)

Image overlays are website screenshots, GitHub social cards, or tool logos shown briefly when the speaker mentions a tool or resource. They differ from text overlay cards in sizing and placement.

### Asset selection hierarchy
1. **GitHub social cards** — best for tools/repos. Shows repo name, one-line description, star count, and logo. Instantly recognizable by dev audiences. Use `gather_assets.py` with the GitHub repo URL to fetch (e.g., `https://github.com/casey/just`).
2. **Website homepage OG image** — use only if it's a clean, branded graphic. Avoid landing pages that have navigation links, non-English text, or multiple CTAs — these look confusing at small overlay size. Always view the OG image before using it.
3. **Full-page screenshot** — last resort. Text-heavy pages are unreadable at 30% frame width.

**Always view the fetched image before placing it.** Some OG images look great at full size but are confusing at overlay size (e.g., the just.systems OG image has "j u s t" with Discord/GitHub links and Chinese characters — not useful as a small overlay).

### Calibrated values for image overlays (3840x2160 timeline, 1080p render)

Image overlays should be **smaller than text overlays** and placed in a **corner** (typically upper-right to avoid the webcam in bottom-right).

| Image native size | ZoomX/Y | Approx. frame coverage |
|---|---|---|
| 1280x800 (OG image) | 0.35 | ~30% of frame width |
| 1200x600 (GitHub card) | 0.35 | ~28% of frame width |
| 1920x1080 (full screenshot) | 0.25-0.30 | ~30% of frame width |

**Positioning for upper-right corner:**
- `Pan=900`, `Tilt=550` — places image in upper-right, clear of webcam and code content
- Adjust Pan higher (950+) if the image is wider than expected
- Adjust Tilt lower (400-500) if it clips the top title bar

### Timing rules
- Show image overlays for **4-5 seconds** — long enough to register, short enough to not be distracting
- **Don't overlap with text overlays** on the same topic. Sequence them: image card first (visual intro) → image fades → text takeaway appears
- Place image overlays when the speaker **first names the tool**, not when they're deep into explaining it

### Compositing cards with URLs

Add a URL bar below GitHub social cards so viewers know where to find the tool. Use ffmpeg to vstack the card with a rendered URL strip:

```bash
ffmpeg -y \
  -i card.png \
  -f lavfi -i "color=c=0xF6F8FA:s=1200x60:d=1" \
  -filter_complex "[1:v]drawtext=fontfile=/System/Library/Fonts/HelveticaNeue.ttc\
:text='github.com/owner/repo':fontcolor=0x0969DA:fontsize=32\
:x=(w-text_w)/2:y=(h-text_h)/2[url];[0:v][url]vstack" \
  -update 1 -frames:v 1 card_with_url.png
```

This creates a composite that looks like a social media link preview — card + clickable-looking URL below in blue text on light gray background.

### Adding drop shadows to image cards

Light-background cards blend into light IDE backgrounds. Add a subtle drop shadow to make them float:

```bash
# Create shadow layer (padded + blurred original)
ffmpeg -y -i card.png \
  -vf "pad=w=iw+20:h=ih+20:x=10:y=10:color=0x00000040,boxblur=4:4" \
  -update 1 -frames:v 1 /tmp/shadow.png

# Composite original on top of shadow
ffmpeg -y -i /tmp/shadow.png -i card.png \
  -filter_complex "[0:v][1:v]overlay=7:7" \
  -update 1 -frames:v 1 card_with_shadow.png
```

### Asset selection: pick the most informative card per tool

Don't default to one source for all tools. Evaluate per tool:

1. **Check the tool's website OG card first** — if it exists and looks good (branded, clean, readable at small size, includes the URL), use it. Example: `airwebframework.org` has a beautiful branded OG card with the tagline and URL already included.
2. **Fall back to GitHub social card** if the website has no OG image, a confusing OG image (navigation links, non-English text, multiple CTAs), or a text-heavy docs page. Example: `just.systems` has an OG image with Japanese characters and Discord links — not useful as a small overlay, so `github.com/casey/just` is better.
3. **Add a URL bar** (ffmpeg vstack technique above) only if the card doesn't already include the URL.
4. **Link to the canonical repo, not a fork.** Always verify you're using the original (e.g., `feldroy/air` not a personal fork).

### Key learnings
- **OG/social cards > full screenshots** for small overlay use. Text-heavy pages are unreadable at 30% frame size.
- **Website OG cards > GitHub cards** when the website has a well-designed one — they're more branded and visually distinctive.
- **GitHub social cards** are the reliable fallback — they always exist and show name, description, stars.
- **Add drop shadows** to light-background cards so they pop against light IDE backgrounds.
- **Always view OG images before using them.** Some look great at full size but are confusing at overlay size (e.g., landing pages with nav links, non-English text, or multiple CTAs).
- **Use a separate track** (track 3) for image overlays to keep them independent from text overlays (track 2).
- **Always test with render→screenshot** — the coordinate system is non-linear and hard to predict.

## Text Overlays via Fusion Comp

Two approaches, depending on needs:

**Approach 1: Fusion Text+ on existing clips (animated text)**
Add text directly to a clip's Fusion composition. Supports keyframe animation (fade, size, position) via BezierSpline. See `video-annotations/references/technical-learnings.md` for the full pattern.

```python
item = timeline.GetItemListInTrack("video", 1)[0]
comp = item.GetFusionCompByIndex(1)
text = comp.AddTool("TextPlus")
text.SetInput("StyledText", "My Text")
text.SetInput("Font", "Arial")
text.SetInput("Size", 0.07)
text.SetInput("Center", {1: 0.5, 2: 0.12})

# Animate with BezierSpline (SetInput with frame number does NOT keyframe)
text.Opacity = comp.BezierSpline({})
text.Opacity[0] = 0.0
text.Opacity[30] = 1.0

# Wire: MediaIn -> Merge(+Text) -> MediaOut
merge = comp.AddTool("Merge")
merge.Background = comp.FindTool("MediaIn1")
merge.Foreground = text
comp.FindTool("MediaOut1").Input = merge
```

**Approach 2: Render text as PNG image overlay (static labels)**
For simple static labels without animation, render as PNG via ffmpeg and place on an overlay track. See "Placing Overlays on Higher Tracks" section above.

**Avoid `InsertFusionTitleIntoTimeline("Text+")`** — it inserts at the playhead and you cannot control which track it lands on.
