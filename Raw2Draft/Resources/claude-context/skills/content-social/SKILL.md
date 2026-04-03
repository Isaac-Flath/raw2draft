---
name: content-social
description: Generate a social media post from a blog post. Use when user wants to create distribution content.
---

# /content-social

Generate a social media post from the blog post using the gemini-3 skill.

## Prerequisite

Requires a blog post in `posts/`. If missing, run `/content-blog` first. Find the post by checking the project's `project:` field in frontmatter, or by slug matching.

## Output

| Format | Output | Description |
|--------|--------|-------------|
| Social | `social/social.md` | Hook from intro, drives to blog post |

## Working Directory

Content Conductor launches Claude from the project directory (`projects/<id>`). Paths below are relative to that directory.

## How to Generate

```bash
uv run .claude/skills/gemini-3/scripts/query.py \
  "Generate content following the format instructions." \
  --context references/writing-style.md \
  --context content/blog.md \
  --context .claude/skills/content-social/references/prompts/social/social.md \
  > social/social.md
```

The `--context` flag:
- Reads each file and prepends it to the prompt
- Avoids shell escaping issues
- Reports which files were loaded and their sizes

## See Also

- `/content-status` - Check what's been generated
