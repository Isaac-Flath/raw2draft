---
name: fusion-animations
description: Add animated overlays (circles, text, shapes) to video clips in DaVinci Resolve via Fusion scripting API.
---

# Fusion Animations Skill

Add animated overlays to video clips in DaVinci Resolve using the Fusion scripting API. Shapes draw on, text fades in, and everything composites over the existing video.

## Prerequisites

- DaVinci Resolve Studio must be running
- Python 3.6+ with Resolve scripting module access

## Connection Boilerplate

```python
import sys
sys.path.insert(0, "/Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/Scripting/Modules")
import DaVinciResolveScript as dvr

resolve = dvr.scriptapp("Resolve")
pm = resolve.GetProjectManager()
proj = pm.GetCurrentProject()
tl = proj.GetCurrentTimeline()
item = tl.GetItemListInTrack("video", 1)[0]
comp = item.GetFusionCompByIndex(1)

media_in = comp.FindTool("MediaIn1")
media_out = comp.FindTool("MediaOut1")
```

Every clip has a default Fusion comp with `MediaIn1` and `MediaOut1`. All overlays get inserted between them.

## Core Concepts

### Node Chain

All overlays must form a chain ending at MediaOut. The pattern is:

```
MediaIn -> Merge1(+overlay1) -> Merge2(+overlay2) -> ... -> MediaOut
```

Each Merge node takes a Background (the video chain) and Foreground (the overlay). If MediaOut gets disconnected, the video goes black.

### Static vs Animated Properties

```python
# Static — use SetInput
text.SetInput("StyledText", "Hello!")
text.SetInput("Font", "Arial")

# Animated — use BezierSpline then set keyframes by frame number
text.Opacity = comp.BezierSpline({})
text.Opacity[0] = 0.0    # frame 0: invisible
text.Opacity[30] = 1.0   # frame 30: fully visible
```

**SetInput with a frame number does NOT create keyframes.** Only BezierSpline works for animation.

### Coordinate System

- Normalized 0-1 (not pixels)
- Center of frame: `{1: 0.5, 2: 0.5}`
- Convert from pixels: `fusion_x = pixel_x / 1920`, `fusion_y = 1.0 - (pixel_y / 1080)` (Y is inverted)

### Node Wiring

Use property assignment:
```python
merge.Background = media_in     # video chain in
merge.Foreground = text          # overlay in
media_out.Input = merge          # output
```

## Tested Recipes

### Draw-On Circle

A circle that progressively traces itself on screen (like hand-drawn).

```python
bg = comp.AddTool("Background")
bg.SetInput("TopLeftRed", 1.0)
bg.SetInput("TopLeftGreen", 0.2)
bg.SetInput("TopLeftBlue", 0.2)
bg.SetInput("TopLeftAlpha", 1.0)

ellipse = comp.AddTool("EllipseMask")
ellipse.SetInput("Center", {1: 0.5, 2: 0.5})
ellipse.SetInput("Width", 0.25)
ellipse.SetInput("Height", 0.25)
ellipse.SetInput("BorderWidth", 0.012)
ellipse.SetInput("Solid", 0)          # ring, not filled
ellipse.SetInput("SoftEdge", 0.005)

# Animate draw-on via WriteLength
ellipse.WriteLength = comp.BezierSpline({})
ellipse.WriteLength[0] = 0.0          # nothing visible
ellipse.WriteLength[30] = 1.0         # fully drawn

bg.EffectMask = ellipse

merge = comp.AddTool("Merge")
merge.Background = media_in
merge.Foreground = bg
media_out.Input = merge
```

Key properties for draw-on:
- `WriteLength`: 0.0 (nothing) to 1.0 (full shape) — animate this for draw-on
- `WritePosition`: where drawing starts (0.0 = top, 0.25 = right, 0.5 = bottom, 0.75 = left)
- `Solid: 0` + `BorderWidth` makes it a stroke/ring instead of filled

### Animated Text Overlay

Text that fades in and grows.

```python
text = comp.AddTool("TextPlus")
text.SetInput("StyledText", "Hello!")
text.SetInput("Font", "Arial")
text.SetInput("Size", 0.07)
text.SetInput("Center", {1: 0.5, 2: 0.12})   # bottom center
text.SetInput("Red1", 1.0)
text.SetInput("Green1", 1.0)
text.SetInput("Blue1", 1.0)

# Fade in
text.Opacity = comp.BezierSpline({})
text.Opacity[0] = 0.0
text.Opacity[30] = 1.0

# Size grow
text.Size = comp.BezierSpline({})
text.Size[0] = 0.04
text.Size[30] = 0.07

merge = comp.AddTool("Merge")
merge.Background = media_in
merge.Foreground = text
media_out.Input = merge
```

### Chaining Multiple Overlays

```python
merge1 = comp.AddTool("Merge")
merge1.Background = media_in
merge1.Foreground = overlay1

merge2 = comp.AddTool("Merge")
merge2.Background = merge1
merge2.Foreground = overlay2

media_out.Input = merge2
```

## Available Tools

| Tool | Use | Key Properties |
|------|-----|----------------|
| `TextPlus` | Text overlays | StyledText, Font, Size, Center, Red1/Green1/Blue1, Opacity |
| `Background` | Solid color fill | TopLeftRed/Green/Blue/Alpha |
| `EllipseMask` | Circles, ovals | Center, Width, Height, BorderWidth, Solid, WriteLength, WritePosition, SoftEdge |
| `RectangleMask` | Rectangles | Center, Width, Height, CornerRadius, BorderWidth, Solid, WriteLength, WritePosition |
| `Merge` | Compositing | Background (input), Foreground (input) |

## Inspecting and Cleaning Up

```python
# List all tools and connections
tools = comp.GetToolList()
for t in tools.values():
    print(t.Name, t.ID)
    for inp in t.GetInputList().values():
        conn = inp.GetConnectedOutput()
        if conn:
            print(f"  {inp.GetAttrs()['INPS_ID']} <- {conn.GetTool().Name}")

# Delete a tool
comp.FindTool("Text1").Delete()

# Reconnect MediaOut after cleanup
media_out.Input = media_in  # direct passthrough (no overlays)
```

## Gotchas

- **BezierSpline required for animation.** `SetInput("Prop", value, frame)` does NOT keyframe. Always use `tool.Prop = comp.BezierSpline({})` then `tool.Prop[frame] = value`.
- **Don't break the chain.** If you delete a node that MediaOut depends on, video goes black. Always reconnect `media_out.Input` after deleting nodes.
- **Preserve MediaIn1/MediaOut1/Left/Right.** These are built-in — never delete them.
- **EllipseMask Solid=0 for strokes.** Default is filled. Set `Solid=0` and use `BorderWidth` for ring/stroke shapes.

## References

- `references/resolve_scripting_api.txt` — Full Blackmagic API reference
- `video-resolve/references/api_practical_notes.md` — Timeline, overlays, markers
- `video-annotations/references/technical-learnings.md` — Additional Fusion patterns
