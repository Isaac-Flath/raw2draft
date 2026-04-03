#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "google-api-python-client",
#     "google-auth-oauthlib",
#     "google-auth-httplib2",
#     "pypandoc",
# ]
# ///
"""Push a markdown file to Google Docs for review.

Converts markdown → DOCX (via pypandoc/pandoc) with embedded images,
uploads to Google Drive with conversion to native Google Docs format,
and tracks the document in docs.json.

Requires pandoc: brew install pandoc
"""

import argparse
import json
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

import pypandoc
from google.oauth2.credentials import Credentials
from google.auth.transport.requests import Request
from googleapiclient.discovery import build
from googleapiclient.http import MediaFileUpload

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
    if docs_path.exists():
        return json.loads(docs_path.read_text())
    return {"files": []}


def save_docs_json(project_dir: Path, data: dict) -> None:
    """Save docs.json to project directory."""
    docs_path = project_dir / "docs.json"
    docs_path.write_text(json.dumps(data, indent=2) + "\n")


def find_file_entry(data: dict, local_path: str) -> dict | None:
    """Find an existing entry for a local file in docs.json."""
    for entry in data["files"]:
        if entry["local_path"] == local_path:
            return entry
    return None


def convert_md_to_docx(md_path: Path, project_dir: Path) -> Path:
    """Convert markdown to DOCX with embedded images via pandoc."""
    docx_path = Path(tempfile.mktemp(suffix=".docx"))
    pypandoc.convert_file(
        str(md_path),
        "docx",
        outputfile=str(docx_path),
        extra_args=["--resource-path", str(project_dir)],
    )
    return docx_path


def upload_docx(drive_service, docx_path: Path, title: str) -> dict:
    """Upload DOCX to Google Drive, converting to Google Docs format."""
    file_metadata = {
        "name": title,
        "mimeType": "application/vnd.google-apps.document",
    }
    media = MediaFileUpload(
        str(docx_path),
        mimetype="application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        resumable=True,
    )
    file = drive_service.files().create(
        body=file_metadata,
        media_body=media,
        fields="id,webViewLink",
    ).execute()
    return file


def share_doc(drive_service, doc_id: str, email: str) -> None:
    """Share a document with commenter access."""
    permission = {
        "type": "user",
        "role": "commenter",
        "emailAddress": email,
    }
    drive_service.permissions().create(
        fileId=doc_id,
        body=permission,
        sendNotificationEmail=False,
    ).execute()
    print(f"  Shared with {email} (commenter)")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Push a markdown file to Google Docs for review"
    )
    parser.add_argument(
        "project_dir",
        help="Project directory path",
    )
    parser.add_argument(
        "--file",
        default="content/blog.md",
        help="Markdown file to push (relative to project dir, default: content/blog.md)",
    )
    parser.add_argument(
        "--share",
        action="append",
        default=[],
        metavar="EMAIL",
        help="Email address to share with (can be repeated)",
    )
    parser.add_argument(
        "--title",
        help="Document title (default: derived from file content or filename)",
    )
    args = parser.parse_args()

    project_dir = Path(args.project_dir).resolve()
    md_path = project_dir / args.file

    if not md_path.exists():
        print(f"Error: File not found: {md_path}")
        return 1

    # Read markdown to extract title if not provided
    md_content = md_path.read_text()
    title = args.title
    if not title:
        for line in md_content.splitlines():
            if line.startswith("# "):
                title = line[2:].strip()
                break
        if not title:
            title = md_path.stem.replace("-", " ").replace("_", " ").title()

    # Load existing docs.json
    data = load_docs_json(project_dir)
    existing = find_file_entry(data, args.file)

    # Determine version number
    version = 1
    if existing:
        version = existing.get("version", 1) + 1
        title_with_version = f"{title} (v{version})"
    else:
        title_with_version = title

    print(f"Converting {args.file} to DOCX...")
    docx_path = convert_md_to_docx(md_path, project_dir)

    try:
        creds = get_credentials()
        drive_service = build("drive", "v3", credentials=creds)

        print(f"Uploading to Google Docs as '{title_with_version}'...")
        file = upload_docx(drive_service, docx_path, title_with_version)
        doc_id = file["id"]
        doc_url = file["webViewLink"]

        now = datetime.now(timezone.utc).isoformat()

        # Collect emails to share with
        share_emails = set(args.share)
        if existing:
            # Auto-share with previous collaborators
            for email in existing.get("shared_with", []):
                share_emails.add(email)

        for email in share_emails:
            share_doc(drive_service, doc_id, email)

        # Update docs.json
        new_entry = {
            "doc_id": doc_id,
            "doc_url": doc_url,
            "version": version,
            "pushed_at": now,
        }

        if existing:
            # Add current to history before updating
            history_entry = {
                "doc_id": existing["doc_id"],
                "doc_url": existing["doc_url"],
                "version": existing["version"],
                "pushed_at": existing["pushed_at"],
            }
            existing.setdefault("history", []).append(history_entry)

            existing["doc_id"] = doc_id
            existing["doc_url"] = doc_url
            existing["title"] = title_with_version
            existing["pushed_at"] = now
            existing["last_pulled_at"] = None
            existing["version"] = version
            existing["shared_with"] = sorted(share_emails)
        else:
            data["files"].append({
                "local_path": args.file,
                "doc_id": doc_id,
                "doc_url": doc_url,
                "title": title_with_version,
                "pushed_at": now,
                "last_pulled_at": None,
                "version": version,
                "shared_with": sorted(share_emails),
                "history": [],
            })

        save_docs_json(project_dir, data)

        print()
        print(f"Google Doc: {doc_url}")
        print(f"Version: {version}")
        print(f"Tracked in: docs.json")
        return 0

    finally:
        docx_path.unlink(missing_ok=True)


if __name__ == "__main__":
    sys.exit(main())
