# Raw2Draft

> [!WARNING]
> This app runs Claude Code with `--dangerously-skip-permissions` (YOLO mode). All AI-initiated actions — file writes, shell commands, etc. — are automatically approved without prompting. Use at your own risk and only with content you trust.

Isaac Flath's personal writing tool.

Markdown editor with an integrated Claude Code terminal for macOS.

## Installation

Requires [just](https://github.com/casey/just) and Xcode.

```bash
git clone https://github.com/Isaac-Flath/raw2draft.git
cd raw2draft
just build
just install
```

This compiles a Release build, copies it to `/Applications/Raw2Draft.app`, and installs the `draft` CLI to `~/.local/bin/draft` (make sure `~/.local/bin` is on your `PATH`).

### First launch

- **Content Studio mode** activates automatically when you open a directory containing a `posts/` subdirectory
- **API keys**: Add via Settings (`Cmd+,`), or edit `~/.raw2draft/.env` directly

## Features

This is a personal tool that I build for myself. Some things are well-tested and used daily, some are experimental, and some are brand new and barely tested. It all ships together. Use what works for you.

- Split-pane markdown editor (CodeMirror 6) + Claude Code terminal
- Content Studio mode for managing blog posts and content projects
- Live markdown preview with heading outline
- Agent skills and reference docs cloned from public starter repos on first launch
- Blog post browser with draft/published/scheduled status
- Command palette (`Cmd+P`) for discovering shortcuts and skills
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

There is no special Claude Code integration. The app runs a terminal and launches the Claude Code harness in a terminal with no app specific modifications. It uses [agent skills](https://docs.anthropic.com/en/docs/claude-code/skills) to give it additional behavior.

## Skills and knowledge base

On first launch, Raw2Draft clones two public starter repos into `~/.raw2draft/context/`:

- **[agentkb-skills](https://github.com/Isaac-Flath/agentkb-skills)** — Agent skills for content creation, transcription, social media, video editing, and more
- **[agent-starter-wiki](https://github.com/Isaac-Flath/agent-starter-wiki)** — Writing style guides and reference documents

These are passed to Claude Code via `--add-dir` so skills are available as `/slash-commands` and reference docs are in context.

### Customizing

Fork the starter repos and edit them to build your own skill set and knowledge base. The app won't overwrite your changes on subsequent launches.

For a richer setup, install [agentkb](https://github.com/Isaac-Flath/agentkb) to manage your skills and knowledge base with semantic search, git sync, and chat history indexing.

### Resetting

To re-clone the starter repos (replacing your local changes):

```bash
just reset-context
```

Or press **Reset to Defaults** in Settings.

## Just recipes

```bash
just build          # Compile (Release)
just install        # Copy app to /Applications and install the draft CLI
just reset-context  # Move deployed context to Trash (relaunch to get fresh skills)
just refresh        # Build + install + reset context in one step
just test           # Run tests
```

## CLI

The `draft` CLI lets you open files and directories from any terminal:

```bash
draft           # Open current directory
draft .         # Same as above
draft file.md   # Open a specific file
draft --version # Show installed build number
```

## License

GPL-3.0 — see [LICENSE](LICENSE) for details.
