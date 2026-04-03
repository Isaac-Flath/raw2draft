---
name: info
description: /info - Blog Metadata
---

# /info - Blog Metadata

Show valid values for post frontmatter fields.

## Working Directory

Run this skill from the workspace root. Commands reference `public/posts-index.json` at root and are not intended for Content Conductor auto sessions.

## Usage

`/info` - Display all metadata (sections, subsections, series)

## Commands

Run these to get current values from `public/posts-index.json`:

```bash
# Sections
jq -r '[.[].section] | unique | sort' public/posts-index.json

# Subsections
jq -r '[.[].subsection] | unique | sort' public/posts-index.json

# Series
jq -r '[.[].series // empty] | unique | sort' public/posts-index.json
```

Format the output as a readable list for the user.
