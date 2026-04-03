---
name: video-annotations
description: Add animated annotations to video that reinforce the speaker's message via DaVinci Resolve Fusion API. Editorial principles prioritize meaning over decoration.
---

# Video Annotations Skill

Add animated annotations to videos that **reinforce the speaker's message**. Not decoration — communication. Read the top-level `references/annotation-editorial-principles.md` before making ANY annotation decisions.

## The Most Important Rule

**Every annotation must add clarity to the speaker's message.** If it doesn't help the viewer understand what's being said, don't add it. Circling random things on screen is the weakest form of annotation. Prefer creating new visual content (animated text, symbols, conceptual drawings) over highlighting existing elements.

## Prerequisites

- DaVinci Resolve Studio must be running
- `ffmpeg` / `ffprobe` (frame extraction)
- `uv` (Python scripts for coordinate detection)
- Gemini API key in `.env` (`GEMINI_API_KEY=...`)

## Annotation Types (ranked by editorial value)

| Rank | Type | Fusion Tool | When to use |
|------|------|-------------|-------------|
| 1 | Animated text | `TextPlus` | Speaker says key terms — write them on screen as they speak |
| 2 | Emphasis underline/circle | `EllipseMask` | One KEY word in a sentence needs emphasis |
| 3 | Relationship arrows | shapes + masks | Speaker describes flow/connection between things |
| 4 | Highlight box | `RectangleMask` | Region contains dense info viewer might miss |

## Workflow

### Step 1: Transcribe (MANDATORY first step)

Always transcribe before annotating. Annotations must match narration.
```bash
uv run .claude/skills/video-editor/scripts/transcribe.py <video_path>
```

### Step 2: Read transcript and make editorial decisions

Read the transcript with timestamps. For each potential annotation, apply the Transcript Test from `references/annotation-editorial-principles.md`:
1. What is the speaker's key point right now?
2. Does this annotation reinforce that exact point?
3. Would a viewer who only saw the annotation (no audio) understand the message?

**Prefer fewer, higher-value annotations.** 3-6 per 30 seconds max. Sometimes zero is right.

### Step 3: Detect coordinates (when annotating existing elements)

```bash
# Extract frame at annotation timestamp
ffmpeg -ss <seconds> -i <video> -frames:v 1 -update 1 frame.png

# Gemini vision for text AND non-text elements
uv run .claude/skills/video-annotations/scripts/detect_bounds.py frame.png "target description"
```

### Step 4: Build annotations in Fusion

Use the `fusion-animations` skill for implementation details. Annotations are added as Fusion comp nodes on the timeline clip — they're editable in Resolve's UI.

### Step 5: Verify with Gemini and self-review

Extract frames at each annotation timestamp. For each:
1. Look at the frame yourself — does the annotation land on the right element?
2. Send to Gemini for positioning critique
3. Adjust and re-check until every annotation is precisely placed

**Gemini is good at positioning critique but bad at editorial judgment.** Don't ask Gemini what to annotate — that's your job based on the transcript and editorial principles.

## References

Editorial guidance (in top-level `references/`):
- `references/annotation-editorial-principles.md` — **Read this first.** Editorial judgment, mobile-first sizing, what to annotate and why.
- `references/visual-editing-principles.md` — Overlay placement, caption design, mobile-first principles.

Implementation:
- `fusion-animations/SKILL.md` — Fusion API recipes: draw-on circles, animated text, node wiring, coordinate system.
- `references/technical-learnings.md` — Hard-won technical notes: coordinate detection, Gemini usage patterns.

## File Structure

```
scripts/
    detect_bounds.py         # Gemini vision coordinate detection
references/
    technical-learnings.md   # Coordinate detection, Gemini patterns, timing notes
    mixedbread-doc-search.md # Vector search for reference docs
```
