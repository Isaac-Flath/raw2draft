---
name: content-transcribe
description: Transcribe video files using LemonFox (blog) or AssemblyAI (video editing). Use when user has video content to process.
---

# /content-transcribe

Transcribe video using LemonFox or AssemblyAI.

- **Blog posts**: Use LemonFox (default). Segment-level timestamps, clean text.
- **Video editing**: Use AssemblyAI (`--provider assemblyai`). Word-level timestamps, disfluencies preserved for accurate cut detection.

## Usage

```
/content-transcribe
```

## Working Directory

Content Conductor launches Claude from the project directory (`projects/<id>`). Paths below are relative to that directory.

## Run

Blog transcription (LemonFox):
```bash
VIDEO=$(ls source/*.mp4 2>/dev/null | head -1)
uv run .claude/skills/content-transcribe/scripts/transcribe.py "$VIDEO" content
```

Video editing transcription (AssemblyAI):
```bash
uv run .claude/skills/content-transcribe/scripts/transcribe.py --provider assemblyai "$VIDEO" claude-edits
```

## Output

- `<output_dir>/transcript.md` - Full transcript
- `<output_dir>/description.md` - Video description with chapters (LemonFox only)

## After Transcription

Run `/content-blog` to generate content. Screenshots are extracted on-demand during blog generation using `/content-screenshot`.
