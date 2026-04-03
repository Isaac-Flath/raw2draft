---
name: content-blog
description: Generate a blog post from source materials (text, PDFs, images, transcripts). Use when user wants to create a blog post or article.
---

# /content-blog

Generate a blog post using the gemini-3 skill for multimodal content.

## Usage

```
/content-blog
```

## Before Running

If `source/*.mp4` exists but `content/transcript.md` doesn't, run `/content-transcribe` first.

## Working Directory

Run from the monorepo root. The script finds the linked post in `posts/` automatically based on the project directory name.

## Source Materials

Accepts any combination from the project directory:
- `source/*.txt` or `source/*.md` (text files)
- `source/*.pdf` (PDFs)
- `source/*.png`, `source/*.jpg` (images)
- `content/transcript.md` (video transcript)
- `content/description.md` (video description/chapters)
- `screenshots/` (video screenshots, extracted on-demand)

## Run

```bash
# Generate blog post from project, writes to posts/
uv run .claude/skills/content-blog/scripts/generate_blog.py posts/<id>

# Specify a different Gemini model
uv run .claude/skills/content-blog/scripts/generate_blog.py posts/<id> --model gemini-2.5-pro
```

## How It Works

The script:
1. Gathers all source materials from the project directory
2. Builds a comprehensive prompt using Jinja2 templates
3. Calls the `/gemini-3` skill with the prompt and all multimodal files
4. Saves the generated blog post to `posts/<slug>/blog.md` with `draft: true`

## Screenshots

Screenshots must be extracted separately using `/content-screenshot` before or after blog generation.

1. Identify timestamps from the transcript/chapters that need visual illustration
2. Run `/content-screenshot` with those timestamps
3. Reference in the blog: `![Description](screenshots/screenshot-01m30s.png)`

## Output

Saves to `posts/<slug>/blog.md` (as a draft).

## Post-Generation Editing

After the blog is generated, run two Zinsser editing passes using gemini-3 to tighten the prose:

```bash
POST="posts/YYYY-MM-DD-slug/blog.md"

# First pass
uv run .claude/skills/gemini-3/scripts/query.py "Review this blog post and apply Zinsser's writing principles to remove clutter, eliminate weak verbs, cut throat-clearing, and tighten every sentence. Return only the improved blog post in full, no commentary.

ZINSSER PRINCIPLES:
- Strip every sentence to its cleanest components
- No throat-clearing (cut 'In this post' openings)
- No nounism (use verbs not noun clusters)
- No clutter (eliminate qualifiers like 'very', filler phrases like 'in order to')
- Active voice
- Short sentences, short paragraphs
- No dead constructions ('There are', 'It is important')
- Strong verbs (replace is/was/has/make/do/get with specific verbs)
- No AI tells ('dive into', 'leverage', 'utilize')

BLOG POST TO IMPROVE:
$(cat $POST)" --model gemini-2.5-pro > "${POST}.tmp"

mv "${POST}.tmp" "$POST"

# Second pass (same command)
uv run .claude/skills/gemini-3/scripts/query.py "Review this blog post and apply Zinsser's writing principles to remove clutter, eliminate weak verbs, cut throat-clearing, and tighten every sentence. Return only the improved blog post in full, no commentary.

ZINSSER PRINCIPLES:
- Strip every sentence to its cleanest components
- No throat-clearing (cut 'In this post' openings)
- No nounism (use verbs not noun clusters)
- No clutter (eliminate qualifiers like 'very', filler phrases like 'in order to')
- Active voice
- Short sentences, short paragraphs
- No dead constructions ('There are', 'It is important')
- Strong verbs (replace is/was/has/make/do/get with specific verbs)
- No AI tells ('dive into', 'leverage', 'utilize')

BLOG POST TO IMPROVE:
$(cat $POST)" --model gemini-2.5-pro > "${POST}.tmp"

mv "${POST}.tmp" "$POST"
```

Two passes catch clutter the first pass missed and produce tighter prose.

## Customizing Style

- `references/writing-style.md` - Zinsser style guide (shared)
- `.claude/skills/content-blog/references/prompts/blog-generation.md` - Blog instructions
