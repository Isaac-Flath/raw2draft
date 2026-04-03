---
name: content-gdocs
description: Push blog posts to Google Docs for review, then pull comments and suggestions back as feedback for discussion.
---

# /content-gdocs

Push content to Google Docs for collaborative review. Reviewers add comments and suggestions (tracked changes) in Google Docs, then pull that feedback back into the project for discussion with Claude.

## Usage

```bash
# One-time setup
uv run .claude/skills/content-gdocs/scripts/setup_auth.py

# Push blog post to Google Docs
uv run .claude/skills/content-gdocs/scripts/push.py <project-dir>
uv run .claude/skills/content-gdocs/scripts/push.py <project-dir> --file content/blog.md
uv run .claude/skills/content-gdocs/scripts/push.py <project-dir> --share reviewer@example.com

# Pull feedback from Google Docs
uv run .claude/skills/content-gdocs/scripts/pull.py <project-dir>
uv run .claude/skills/content-gdocs/scripts/pull.py <project-dir> --file content/blog.md
```

## Setup (One-Time)

### 1. Google Cloud Project

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project (or select an existing one)
3. Enable the **Google Docs API** and **Google Drive API**:
   - APIs & Services > Library > search "Google Docs API" > Enable
   - APIs & Services > Library > search "Google Drive API" > Enable

### 2. OAuth Credentials

1. Go to APIs & Services > Credentials
2. Click "Create Credentials" > "OAuth client ID"
3. Application type: **Desktop app**
4. Download the JSON file
5. Save it to: `~/.content/google_credentials.json`

### 3. System Dependency

```bash
brew install pandoc
```

Required for markdown-to-DOCX conversion with embedded images.

### 4. Authenticate

```bash
uv run .claude/skills/content-gdocs/scripts/setup_auth.py
```

This opens a browser for Google sign-in and saves a refresh token to `~/.content/google_token.json`.

## Workflow

### Push

1. Reads the markdown file (default: `content/blog.md`)
2. Converts to DOCX via pandoc (preserves headings, formatting, and images)
3. Uploads to Google Drive as a native Google Doc
4. Shares with specified reviewers as "commenter" (can view + suggest, not directly edit)
5. Tracks the document in `docs.json`

Re-pushing creates a **new document** (v2, v3...) to preserve comments on previous versions. Previous collaborators are auto-shared with the new doc.

### Pull

1. Reads `docs.json` to find the Google Doc ID
2. Fetches comments via Drive API (author, quoted text, replies)
3. Fetches suggestions via Docs API (tracked insertions/deletions)
4. Writes structured feedback to `content/feedback.md`

**The feedback file is context for discussion, not auto-apply.** After pulling, review `feedback.md` with Claude to decide what to incorporate, what to push back on, and what to ignore.

## Document Tracking: `docs.json`

Stored in the project directory. Maps local files to Google Doc IDs/URLs.

```json
{
  "files": [
    {
      "local_path": "content/blog.md",
      "doc_id": "1a2b3c...",
      "doc_url": "https://docs.google.com/document/d/1a2b3c.../edit",
      "title": "How I Made My Website",
      "pushed_at": "2026-03-02T14:00:00Z",
      "last_pulled_at": null,
      "version": 1,
      "shared_with": ["reviewer@example.com"],
      "history": []
    }
  ]
}
```

## Limitations

1. **Pandoc system dependency** -- `brew install pandoc` needed for markdown+image conversion
2. **Feedback is discussion context, not auto-apply** -- `feedback.md` is meant for reviewing with Claude
3. **New doc per push** -- re-pushing creates a new Google Doc to preserve comments on old versions
4. **One-time GCP Console setup** -- ~5 min manual process to create project and download credentials
5. **Suggestion parsing is best-effort** -- simple word/phrase replacements parse cleanly; complex structural suggestions may be incomplete
