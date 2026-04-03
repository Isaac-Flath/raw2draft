---
name: content-image
description: Generate AI images for content using Gemini or other image generation APIs. Use when user needs diagrams, illustrations, or visual content.
---

# /content-image

Generate AI images for content.

## Usage

```
/content-image [prompt]
```

## Prerequisites

- `uv` CLI: `brew install uv` or `pip install uv`
- `GEMINI_API_KEY` environment variable

## Working Directory

Content Conductor launches Claude from the project directory (`projects/<id>`). Paths below are relative to that directory.

## Run

```bash
# With explicit output path
uv run .claude/skills/content-image/scripts/generate_image.py "prompt" images/diagram.png

# Or use --project to save to project's images/ directory (auto-generates filename)
uv run .claude/skills/content-image/scripts/generate_image.py "prompt" --project .
```

## Output

Saves to `{project}/images/{descriptive-name}.png`

Insert in content: `![Description](images/filename.png)`

## Style Principles

See `.claude/skills/content-image/references/prompts/image-generation.md` for Tufte-style guidelines:
- Clean background, high data-ink ratio
- Minimal text, clear labels
- No decoration that doesn't add meaning

## Good Prompts

- "Flowchart showing [process]"
- "Diagram illustrating [concept]"
- "Architecture diagram for [system]"
- "Minimalist line drawing of..."
