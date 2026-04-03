---
name: video-resolve
description: Build edited YouTube videos in DaVinci Resolve using its Python scripting API.
---

# Video Resolve Skill

Build edited YouTube videos in DaVinci Resolve using its Python scripting API directly. No wrapper scripts — write inline Python that calls the API via Bash.

## Prerequisites

- **DaVinci Resolve Studio** must be running
- Python 3.6+ with access to Resolve's scripting module

## API Documentation

All API reference material is in `references/`:
- `resolve_scripting_api.txt` — Official Blackmagic API reference (complete)
- `api_practical_notes.md` — Tested patterns, gotchas, and working examples

**Always read `api_practical_notes.md` before writing Resolve API calls.** It documents critical gotchas like the `recordFrame` offset and `mediaType` semantics.

## How to Use

Write inline Python scripts via Bash that call the Resolve API directly. Connection boilerplate:

```python
import sys
sys.path.insert(0, "/Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/Scripting/Modules")
import DaVinciResolveScript as dvr

resolve = dvr.scriptapp("Resolve")
pm = resolve.GetProjectManager()
resolve.OpenPage("edit")
```

## Test Script

`scripts/test_api.py` — Verifies each API operation individually. Run to confirm the API is working.

## Building a Project

When building a project from EDL + overlay + chapter data, write the API calls inline. The key operations:

1. **Create project** — `pm.CreateProject(name)`, set resolution/fps, import source media
2. **Build timeline** — `media_pool.CreateEmptyTimeline(name)`, then `AppendToTimeline` for each kept segment. **Omit `mediaType` for video+audio.**
3. **Get timeline start frame** — `t1_items[0].GetStart()` (typically 108000 for 01:00:00:00 at 30fps)
4. **Add overlay track** — `timeline.AddTrack("video")`
5. **Place overlays** — `AppendToTimeline` with `trackIndex`, `recordFrame` (must include start offset!), `mediaType: 1`
6. **Set overlay transforms** — `item.SetProperty("ZoomX"/"ZoomY"/"Pan"/"Tilt", value)` per overlay
7. **Add markers** — `timeline.AddMarker(frame, color, name, note, duration)`

Each of these is a few lines of Python. No wrapper needed.

## File Structure
```
scripts/
    test_api.py                          # API test suite
references/
    resolve_scripting_api.txt            # Official Blackmagic API docs
    api_practical_notes.md               # Tested patterns and gotchas
```
