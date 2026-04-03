---
name: content-transcribe
description: Transcribe video files and extract chapters. Use when user has video content to process.
---

# /content-transcribe

Transcribe video using LemonFox API.

## Usage

```
/content-transcribe
```

## Working Directory

Content Conductor launches Claude from the project directory (`projects/<id>`). Paths below are relative to that directory.

## Run

```bash
VIDEO=$(ls source/*.mp4 2>/dev/null | head -1)
uv run .claude/skills/content-transcribe/scripts/transcribe.py "$VIDEO" content
```

## Output

- `content/transcript.md` - Full transcript
- `content/description.md` - Video description with chapters (YouTube-compatible format)

## After Transcription

Run `/content-blog` to generate content. Screenshots are extracted on-demand during blog generation using `/content-screenshot`.
