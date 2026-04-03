---
name: blog-schedule
description: /blog-schedule - Manage Post Schedule
---

# /blog-schedule - Manage Post Schedule

View and change post publication dates.

## Working Directory

Run this skill from the workspace root. It uses `scripts/schedule.py` at root and is not intended for Content Conductor auto sessions.

## Commands

**List** (default): `/blog-schedule`
```bash
uv run scripts/schedule.py
```
Shows upcoming, recent, and older posts with series tags.

**Move**: `/schedule move [slug] [YYYY-MM-DD]`
1. Update frontmatter `date` field
2. Rename file to match new date
3. Warn if date conflicts with another post

**Swap**: `/schedule swap [slug1] [slug2]`
Exchange dates between two posts.

## Notes

- Dates use YYYY-MM-DD format
- Files follow `YYYY-MM-DD-slug.md` naming convention
- Posts with `access: members` are extras (subscriber-only). They appear in `/extras` instead of `/writing`
- Run `just sync` after changes to update S3
