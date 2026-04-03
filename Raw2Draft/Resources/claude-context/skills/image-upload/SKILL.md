---
name: image-upload
description: /image-upload - Upload local images in a blog post to S3 and replace paths with hosted URLs.
---

# /image-upload

Upload local images in a blog post to S3 and replace paths with hosted URLs.

## Usage

```bash
cd projects/2026_03_01_my-post
uv run ../../.claude/skills/image-upload/scripts/publish_prep.py .
```

## What it does

1. Reads `content/blog.md` from the project directory
2. Finds all `![alt](path)` markdown image references
3. Skips any that are already HTTP/HTTPS URLs
4. Uploads each local image to S3 with a random hex filename
5. Replaces the local path with the S3 URL in-place
6. Overwrites `content/blog.md` with the updated content

## Requirements

- AWS credentials configured in Settings (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_REGION, S3_BUCKET)
- These are automatically available as environment variables in the app's terminal
