# Raw2Draft

> [!WARNING]
> This app runs Claude Code with `--dangerously-skip-permissions` (YOLO mode). All AI-initiated actions — file writes, shell commands, etc. — are automatically approved without prompting. Use at your own risk and only with content you trust.

Isaac Flath's personal writing tool.

Markdown editor with an integrated Claude Code terminal for macOS.

## Download

Grab the latest DMG from [Releases](https://github.com/Isaac-Flath/raw2draft/releases). Open the DMG and drag Raw2Draft to your Applications folder.

> **Note:** This build is not code-signed or notarized. On first launch, right-click the app and select **Open** to bypass the macOS security prompt.

### First launch

- **Content root**: Set via Settings if using Content Studio mode (needs `posts/` and `projects/` directories)
- **API keys**: Add via Settings, or edit `~/.raw2draft/.env` directly

## Features

This is a personal tool that I build for myself. Some things are well-tested and used daily, some are experimental, and some are brand new and barely tested. It all ships together.  Use what works for you.

- Split-pane markdown editor (CodeMirror 6) + Claude Code terminal
- Content Studio mode for managing blog posts and content projects
- Live markdown preview with heading outline
- Customizable Claude skills and context deployed to `~/.raw2draft/context/`
- Blog post browser with draft/published/scheduled status
- Command palette (Shift+Cmd+K) for discovering shortcuts and skills
- Drag-and-drop image upload to S3
- Social media content generation and scheduling
- Video editing skills (DaVinci Resolve integration)
- Carousel rendering
- Google Docs and YouTube integration

## API keys

Configure in Settings or edit `~/.raw2draft/.env` directly.

| Key | What it's for |
|-----|---------------|
| `GEMINI_API_KEY` | AI provider for Claude CLI |
| `OPENAI_API_KEY` | AI provider for Claude CLI |
| `LEMONFOX_API_KEY` | Transcription |
| `ASSEMBLYAI_API_KEY` | Transcription |
| `AWS_ACCESS_KEY_ID` | Image hosting (S3) |
| `AWS_SECRET_ACCESS_KEY` | Image hosting (S3) |
| `AWS_REGION` | Image hosting (S3) |
| `S3_BUCKET` | Image hosting (S3) |
| `UPLOADPOST_API_KEY` | Social media scheduling |

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

## How Claude Code integration works

There is no special Claude Code integration. The app runs a terminal and launches the Claude Code harness with no modifications. It uses [agent skills](https://docs.anthropic.com/en/docs/claude-code/skills) to give it additional behavior.

## Customizing prompts and skills

On first launch, bundled context is deployed to `~/.raw2draft/context/`. This includes a CLAUDE.md, skills, and reference documents. Edit these files to customize behavior — the app won't overwrite your changes on subsequent launches.

To reset to defaults, delete `~/.raw2draft/context/` and relaunch.

## Building from source

```bash
git clone https://github.com/Isaac-Flath/raw2draft.git
cd raw2draft
open Raw2Draft.xcodeproj
```

Build and run from Xcode (Cmd+R), or use [just](https://github.com/casey/just):

```bash
just build    # Compile (Release). Output goes to Xcode DerivedData.
just install  # Copy app to /Applications and install the `draft` CLI.
just test     # Run tests.
```

`just install` does three things:
1. Copies the built app to `/Applications/Raw2Draft.app` (kills the running instance first)
2. Installs the `draft` CLI to `~/.local/bin/draft`
3. Requires `~/.local/bin` on your `PATH` for the CLI to work

The `draft` CLI lets you open files and directories from any terminal:

```bash
draft           # Open current directory
draft .         # Same as above
draft file.md   # Open a specific file
draft --version # Show installed build number
```

## License

GPL-3.0 — see [LICENSE](LICENSE) for details.
