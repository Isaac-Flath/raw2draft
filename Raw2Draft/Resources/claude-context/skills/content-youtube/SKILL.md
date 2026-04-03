---
name: content-youtube
description: Download YouTube videos to the source directory.
---

# /content-youtube

Download a YouTube video to a project's `source/` directory.

## Usage

```
/content-youtube <youtube-url> [project-path]
```

## Prerequisites

- `uv` CLI: `brew install uv` or `pip install uv`
- `yt-dlp` CLI: `brew install yt-dlp`

## Working Directory

Content Conductor launches Claude from the project directory (`projects/<id>`). Paths below are relative to that directory.

## Run

```bash
# Download into this project's source/ directory
uv run .claude/skills/content-youtube/scripts/download.py "<youtube-url>" source/

# Or rely on the default output_dir ("source/")
uv run .claude/skills/content-youtube/scripts/download.py "<youtube-url>"
```

## Options

- `url` - YouTube video URL (required)
- `output_dir` - Output directory (required)
- `--max-size` - Maximum file size in MB (default: 500)
- `--audio-only` - Download audio only (mp3)

## Output

Downloads video to `source/{video-title}.mp4`

## After Download

Run `/content-transcribe` to transcribe the video.
