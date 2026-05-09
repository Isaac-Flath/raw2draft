---
name: s3
description: Work with the repo's S3-backed post assets and publishing scripts.
---

Use this skill for S3 post asset workflows.

Workflow:

1. Inspect the repo's scripts and `justfile` for S3 commands.
2. Verify paths and target bucket behavior before upload or delete operations.
3. Prefer dry-run or read-only checks before remote writes when available.
4. Report exact files affected.
