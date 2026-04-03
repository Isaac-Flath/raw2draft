# Raw2Draft

Markdown editor with an integrated Claude CLI terminal for macOS. Personal tool, open sourced for others to use.

## What it does

- Split-pane markdown editor (CodeMirror 6) + Claude Code terminal
- Content Studio mode for managing blog posts and content projects
- Drag-and-drop image upload to S3
- Customizable Claude skills and context deployed to `~/.raw2draft/context/`
- Live markdown preview with heading outline

## Requirements

- macOS 14.0+
- Xcode 15+ (to build)
- [Claude CLI](https://docs.anthropic.com/en/docs/claude-code) installed

## Quick start

```bash
git clone https://github.com/Isaac-Flath/raw2draft.git
cd raw2draft
open Raw2Draft.xcodeproj
```

Build and run from Xcode (Cmd+R).

On first launch, configure your settings:
- **Content root**: Set via Settings if using Content Studio mode (needs `posts/` and `projects/` directories)
- **API keys**: Add to `.env` in your content root, or set as environment variables

## API keys

**Required (at least one):**
- `GEMINI_API_KEY` or `OPENAI_API_KEY` — AI provider for Claude CLI

**Optional:**
- `LEMONFOX_API_KEY` — transcription
- `ASSEMBLYAI_API_KEY` — transcription (alternative)
- `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`, `S3_BUCKET` — image hosting
- `UPLOADPOST_API_KEY` — social media scheduling

## Customizing prompts and skills

On first launch, bundled context is deployed to `~/.raw2draft/context/`. This includes a CLAUDE.md, skills, and reference documents. Edit these files to customize behavior — the app won't overwrite your changes on subsequent launches.

To reset to defaults, delete `~/.raw2draft/context/` and relaunch.

### Skill format

Each skill lives in `.claude/skills/<name>/SKILL.md` with frontmatter:

```markdown
---
name: my-skill
description: /my-skill - What it does
---

# /my-skill - What it does

Instructions for Claude...
```

## License

MIT
