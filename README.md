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

## Blog posts

Content Studio mode includes a blog post browser. It expects a `posts/` directory inside your content root, with each post as a dated directory containing a `blog.md` file:

```
<content-root>/
  posts/
    2025-03-15-my-first-post/
      blog.md
      image.png
      ...
    2025-04-01-another-post/
      blog.md
```

### Frontmatter

Each `blog.md` starts with YAML frontmatter between `---` delimiters. The app uses these fields:

```yaml
---
title: "My Post Title"
date: "2025-03-15"
section: "tutorials"
draft: true
---

Post content here...
```

| Field | Required | Description |
|-------|----------|-------------|
| `title` | No | Display name in the post browser. Falls back to the directory slug. |
| `date` | No | `YYYY-MM-DD` format. Used for sorting, filtering recent posts, and determining published vs scheduled status. |
| `section` | No | Grouping label. Populates the section filter dropdown. |
| `draft` | No | `true` or `false`. Draft posts show a gold indicator; omitting defaults to published. |

You can include any additional frontmatter fields your blog needs (e.g., `description`, `categories`, `author`, `image`) — the app will ignore them but preserve them in the file.

A post with a `date` in the future and `draft: false` is shown as "scheduled" (indigo indicator). Otherwise it's "published" (green).

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
