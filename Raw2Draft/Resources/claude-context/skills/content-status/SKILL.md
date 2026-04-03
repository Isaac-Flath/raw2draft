---
name: content-status
description: Show project status - what source files exist, what content has been generated, what's missing.
---

# /content-status

Show project status.

## Usage

```
/content-status [project-path]
```

## Working Directory

Content Conductor launches Claude from the project directory (`projects/<id>`). Paths below are relative to that directory.

## Run

```bash
# Current project status
uv run .claude/skills/content-status/scripts/status.py .
```

Note: Listing all projects requires running the script from the workspace root because it looks for `./projects/`.

## Output

Shows which files exist and their status:

```
Project: my-project

Source Materials:
  ✓ source/video.mp4 (15:32)
  ✓ source/notes.txt
  ✓ source/sources.json (2 URLs)

Generated Content:
  ✓ content/transcript.md (4,532 words)
  ✓ content/blog.md (2,847 words)
  ✗ content/description.md (not generated)

Social Media:
  ✓ social/text-small.md
  ✗ social/video-short.md (not generated)

Screenshots: 32 files
```
