---
name: publish
description: /publish - Publish a Blog Post
---

# /publish - Publish a Blog Post

Validate, remove draft flag, sync to S3, and index for search.

## Working Directory

Run this skill from the workspace root.

## Usage

```
/publish [slug-or-path]
```

## Steps

1. **Find the post** from `$ARGUMENTS` (path, slug, or ask user). Search `posts/` for the file and confirm with the user.

2. **Validate frontmatter** - prompt for missing required fields:
   - `title`, `description`, `date` (YYYY-MM-DD) - required
   - `section`, `subsection` - required (see below)
   - `series` - optional (`writing-for-ai-writers`, `learning-from-failure`, `retrieval-fundamentals`)
   - `image` - optional (S3 URL recommended)
   - `access` - optional. Set to `members` for subscriber-only extras posts. Omit or set to `public` for regular posts.

3. **Handle image** - if missing, ask for S3 URL for the image.

4. **Remove draft flag** - set `draft: false` or remove the `draft: true` line from frontmatter.

## Post Types

- **Regular posts** (`access: public` or omitted): appear in public index, RSS, search, and `/writing`
- **Extras posts** (`access: members`): subscriber-only. Excluded from public index, RSS, and search. Appear only in `/extras` for authenticated subscribers and via direct URL with auth. Extras posts still need `draft: false` to be published.

5. **Publish**: `just publish <slug>`

6. **Report** title, slug, section, image status, publication date

## Valid Values

Use `/info` to look up valid sections, subsections, and series from existing posts.
