---
name: content-init
description: Initialize a new content project with the standard directory structure in projects). Use when user wants to create a new blog post and one doesn't exist for it.
---

# /content-init

Initialize a new content project.

## Usage

```
/content-init <title>
```

## Structure

Creates project in `projects/YYYY_MM_DD_<title>/`:

```
projects/
  2026_01_21_my-project/
    content/
    source/
    screenshots/
    social/
```

## Working Directory

Content Conductor launches Claude from the project directory (`projects/<id>`). This script writes to `./projects/` relative to the current working directory, so it must be run from the workspace root.

## Run

From the app root:
```bash
uv run .claude/skills/content-init/scripts/init.py "<title>"
```

## Next Steps

1. Add source content to `source/` (video, text files, PDFs)
2. Run `/content-youtube <url>` to download a video
3. Run `/content-transcribe` to transcribe video content
4. Run `/content-blog` to generate the blog post
