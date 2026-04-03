---
name: video-chapters
description: Generate YouTube chapter markers from transcript content.
---

# Video Chapters Skill

Generate YouTube chapter markers by reading the transcript and identifying topic boundaries. **No script — do this by reading the transcript and reasoning about where topics change.**

## Output Directory

**All outputs go in `<project_root>/claude-edits/`.**

```
<project_root>/claude-edits/
    <video_stem>_chapters.txt       # YouTube-format chapter list
    <video_stem>_chapters.json      # Structured chapter data with timeline times
```

## How to Generate Chapters

1. Read the transcript (from `_analysis.json` or `_review.md`)
2. Identify where the speaker shifts topics — look for:
   - Explicit transitions ("next", "moving on", "so now let's", "another thing")
   - Long pauses between topics
   - Structural cues ("first", "second", "the last thing")
   - Vocabulary shifts (different tools, concepts, or areas being discussed)
3. Write a short, descriptive title for each chapter (not raw transcript text)
4. Map chapter timestamps through the EDL to get edited timeline positions
5. Aim for 5-12 chapters for a typical 10-minute video. Too many = overwhelming, too few = useless.

## Mapping Source Time to Timeline Time

Chapters reference source timestamps, but the edited video has cuts. To map:

```python
# Build map from EDL kept segments
timeline_pos = 0.0
for seg in kept_segments:
    if source_time >= seg["start"] and source_time <= seg["end"]:
        timeline_time = timeline_pos + (source_time - seg["start"])
    timeline_pos += seg["end"] - seg["start"]
```

## Output Format

**`_chapters.txt`** (paste directly into YouTube description):
```
0:00 Introduction
0:42 The Just File
1:48 Running Scripts with AI Agents
...
```

**`_chapters.json`** (for Resolve markers):
```json
{
  "chapters": [
    {"source_time": 0.0, "title": "Introduction", "timeline_time": 0.0},
    {"source_time": 51.3, "title": "The Just File", "timeline_time": 42.0}
  ]
}
```

## What Makes Good Chapter Titles

- Short (3-8 words)
- Descriptive of what the viewer will learn in that section
- Not raw transcript text ("See see here what you'll see" is bad)
- Consistent style across chapters
