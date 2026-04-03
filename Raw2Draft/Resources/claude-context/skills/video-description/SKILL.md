---
name: video-description
description: Generate YouTube video description, tags, and metadata.
---

# Video Description Skill

Generate YouTube video description, tags, and metadata. **No script — write the description by reading the transcript and reasoning about the content.**

## Output

```
<project_root>/claude-edits/
    <video_stem>_description.md     # YouTube description + metadata
```

## How to Generate

1. Read the transcript and understand what the video is about
2. Write:
   - **Title suggestions** (3 options, under 70 chars, specific and compelling)
   - **Summary** (2-3 sentences, written fresh — not copy-pasted from transcript)
   - **Chapters** (from `_chapters.txt` if available)
   - **Resources/links** mentioned in the video (with actual URLs)
   - **Tags** (relevant keywords for YouTube search, 15-25 tags)
   - **CTA** (newsletter, subscribe link, etc.)

## What Makes Good YouTube Descriptions

- **Summary**: Write it like a tweet — concise, clear, tells the viewer what they'll learn. Don't dump raw transcript sentences.
- **Title suggestions**: Specific > generic. "My Workflow with Just, UV Scripts, and AI Agents" > "Understanding Tools"
- **Tags**: Mix of broad ("developer workflow", "productivity") and specific ("just command runner", "uv scripts python")
- **Links**: Include actual URLs for tools/resources mentioned. Verify they exist.

## Output Format

```markdown
<!-- TITLE SUGGESTIONS -->
<!-- 1. ... -->
<!-- 2. ... -->
<!-- 3. ... -->

## Summary
[2-3 sentences]

[CTA with link]

## Chapters
[from _chapters.txt]

## Resources
- [Resource Name](URL)

## Tags
tag1, tag2, tag3, ...
```
