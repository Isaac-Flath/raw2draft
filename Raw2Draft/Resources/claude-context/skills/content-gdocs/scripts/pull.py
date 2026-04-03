#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "google-api-python-client",
#     "google-auth-oauthlib",
#     "google-auth-httplib2",
# ]
# ///
"""Pull comments and suggestions from a Google Doc into feedback.md.

Reads docs.json to find the Google Doc ID, fetches comments via
Drive API and suggestions via Docs API, and writes a structured
feedback file for discussion with Claude.
"""

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

from google.oauth2.credentials import Credentials
from google.auth.transport.requests import Request
from googleapiclient.discovery import build

SCOPES = [
    "https://www.googleapis.com/auth/documents.readonly",
    "https://www.googleapis.com/auth/drive.file",
]
TOKEN_PATH = Path.home() / ".content" / "google_token.json"


def get_credentials() -> Credentials:
    """Load and refresh OAuth credentials."""
    if not TOKEN_PATH.exists():
        print(f"Error: No token found at {TOKEN_PATH}")
        print("Run setup_auth.py first.")
        sys.exit(1)

    creds = Credentials.from_authorized_user_file(str(TOKEN_PATH), SCOPES)
    if creds.expired and creds.refresh_token:
        creds.refresh(Request())
        TOKEN_PATH.write_text(creds.to_json())
    elif not creds.valid:
        print("Error: Token is invalid. Run setup_auth.py again.")
        sys.exit(1)

    return creds


def load_docs_json(project_dir: Path) -> dict:
    """Load docs.json from project directory."""
    docs_path = project_dir / "docs.json"
    if not docs_path.exists():
        print(f"Error: No docs.json found in {project_dir}")
        print("Push a document first with push.py.")
        sys.exit(1)
    return json.loads(docs_path.read_text())


def find_file_entry(data: dict, local_path: str) -> dict | None:
    """Find an existing entry for a local file in docs.json."""
    for entry in data["files"]:
        if entry["local_path"] == local_path:
            return entry
    return None


def fetch_comments(drive_service, doc_id: str) -> list[dict]:
    """Fetch all comments from a Google Doc via Drive API."""
    comments = []
    page_token = None

    while True:
        response = drive_service.comments().list(
            fileId=doc_id,
            fields="comments(id,author,content,quotedFileContent,resolved,createdTime,replies(author,content,createdTime)),nextPageToken",
            includeDeleted=False,
            pageToken=page_token,
        ).execute()

        comments.extend(response.get("comments", []))
        page_token = response.get("nextPageToken")
        if not page_token:
            break

    return comments


def extract_suggestions(doc: dict) -> list[dict]:
    """Extract suggestions (tracked changes) from a Google Doc.

    Parses the document body for text runs with suggestedInsertionIds
    or suggestedDeletionIds, grouping them by suggestion ID.
    """
    suggestions = {}

    body = doc.get("body", {})
    for element in body.get("content", []):
        paragraph = element.get("paragraph")
        if not paragraph:
            continue

        for elem in paragraph.get("elements", []):
            text_run = elem.get("textRun")
            if not text_run:
                continue

            content = text_run.get("content", "")
            suggested_insertions = text_run.get("suggestedInsertionIds", [])
            suggested_deletions = text_run.get("suggestedDeletionIds", [])

            for sid in suggested_insertions:
                suggestions.setdefault(sid, {"inserts": [], "deletes": [], "author": None})
                suggestions[sid]["inserts"].append(content)

            for sid in suggested_deletions:
                suggestions.setdefault(sid, {"inserts": [], "deletes": [], "author": None})
                suggestions[sid]["deletes"].append(content)

    # Try to get author info from suggestedChanges on text style
    suggested_changes = doc.get("suggestedDocumentStyleChanges", {})
    for sid, change in suggested_changes.items():
        if sid in suggestions:
            author = change.get("suggestionsViewMode", {}).get("suggestedBy")
            if author:
                suggestions[sid]["author"] = author

    return [
        {"id": sid, **data}
        for sid, data in suggestions.items()
    ]


def format_feedback(
    doc_title: str,
    doc_url: str,
    comments: list[dict],
    suggestions: list[dict],
) -> str:
    """Format comments and suggestions into markdown."""
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    lines = [
        "# Review Feedback",
        f"Source: [{doc_title}]({doc_url})",
        f"Pulled: {now}",
        "",
    ]

    # Comments section
    open_count = sum(1 for c in comments if not c.get("resolved"))
    resolved_count = sum(1 for c in comments if c.get("resolved"))

    if comments:
        lines.append("## Comments")
        lines.append("")

        for comment in comments:
            author = comment.get("author", {}).get("displayName", "Unknown")
            email = comment.get("author", {}).get("emailAddress", "")
            author_label = email if email else author
            created = comment.get("createdTime", "")
            resolved = comment.get("resolved", False)
            status_tag = " [RESOLVED]" if resolved else ""

            lines.append(f"### {author_label} ({created}){status_tag}")

            quoted = comment.get("quotedFileContent", {}).get("value", "")
            if quoted:
                for quoted_line in quoted.splitlines():
                    lines.append(f"> {quoted_line}")
                lines.append("")

            lines.append(comment.get("content", ""))
            lines.append("")

            replies = comment.get("replies", [])
            if replies:
                lines.append("#### Replies")
                for reply in replies:
                    reply_author = reply.get("author", {}).get("displayName", "Unknown")
                    reply_email = reply.get("author", {}).get("emailAddress", "")
                    reply_label = reply_email if reply_email else reply_author
                    reply_time = reply.get("createdTime", "")
                    lines.append(f"- {reply_label} ({reply_time}): {reply.get('content', '')}")
                lines.append("")

    # Suggestions section
    if suggestions:
        lines.append("## Suggestions (Tracked Changes)")
        lines.append("")

        for suggestion in suggestions:
            author = suggestion.get("author") or "Reviewer"
            lines.append(f"### {author}")

            deleted_text = "".join(suggestion["deletes"]).strip()
            inserted_text = "".join(suggestion["inserts"]).strip()

            if deleted_text:
                lines.append(f'- **Delete:** "{deleted_text}"')
            if inserted_text:
                lines.append(f'- **Insert:** "{inserted_text}"')
            if not deleted_text and not inserted_text:
                lines.append("- *(empty suggestion)*")
            lines.append("")

    # Summary
    lines.append("## Summary")
    if comments:
        lines.append(f"- {len(comments)} comments ({resolved_count} resolved, {open_count} open)")
    else:
        lines.append("- 0 comments")
    if suggestions:
        lines.append(f"- {len(suggestions)} suggestions pending")
    else:
        lines.append("- 0 suggestions")
    lines.append("")

    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Pull review feedback from Google Docs into feedback.md"
    )
    parser.add_argument(
        "project_dir",
        help="Project directory path",
    )
    parser.add_argument(
        "--file",
        default="content/blog.md",
        help="Local file to pull feedback for (default: content/blog.md)",
    )
    parser.add_argument(
        "--output",
        default="content/feedback.md",
        help="Output file path (relative to project dir, default: content/feedback.md)",
    )
    args = parser.parse_args()

    project_dir = Path(args.project_dir).resolve()

    # Look up doc ID from docs.json
    data = load_docs_json(project_dir)
    entry = find_file_entry(data, args.file)

    if not entry:
        print(f"Error: No Google Doc found for '{args.file}' in docs.json")
        print("Push the file first with push.py.")
        return 1

    doc_id = entry["doc_id"]
    doc_url = entry["doc_url"]
    doc_title = entry.get("title", "Untitled")

    print(f"Pulling feedback from: {doc_title}")
    print(f"  Doc: {doc_url}")

    creds = get_credentials()
    drive_service = build("drive", "v3", credentials=creds)
    docs_service = build("docs", "v1", credentials=creds)

    # Fetch comments
    print("  Fetching comments...")
    comments = fetch_comments(drive_service, doc_id)

    # Fetch suggestions
    print("  Fetching suggestions...")
    doc = docs_service.documents().get(
        documentId=doc_id,
        suggestionsViewMode="PREVIEW_SUGGESTIONS_INLINE",
    ).execute()
    suggestions = extract_suggestions(doc)

    # Format and write feedback
    feedback = format_feedback(doc_title, doc_url, comments, suggestions)
    output_path = project_dir / args.output
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(feedback)

    # Update last_pulled_at in docs.json
    entry["last_pulled_at"] = datetime.now(timezone.utc).isoformat()
    docs_path = project_dir / "docs.json"
    docs_path.write_text(json.dumps(data, indent=2) + "\n")

    print(f"\nFeedback written to: {args.output}")
    print(f"  {len(comments)} comments, {len(suggestions)} suggestions")
    return 0


if __name__ == "__main__":
    sys.exit(main())
