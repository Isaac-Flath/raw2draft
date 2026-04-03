#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "google-api-python-client",
#     "google-auth-oauthlib",
#     "google-auth-httplib2",
# ]
# ///
"""One-time OAuth setup for Google Docs/Drive API access.

Reads client credentials from ~/.content/google_credentials.json,
opens a browser for Google sign-in, and saves the refresh token
to ~/.content/google_token.json.
"""

import os
import sys
from pathlib import Path

os.environ["OAUTHLIB_RELAX_TOKEN_SCOPE"] = "1"

from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow
from google.auth.transport.requests import Request
from googleapiclient.discovery import build

SCOPES = [
    "https://www.googleapis.com/auth/documents.readonly",
    "https://www.googleapis.com/auth/drive.file",
]

CREDENTIALS_PATH = Path.home() / ".content" / "google_credentials.json"
TOKEN_PATH = Path.home() / ".content" / "google_token.json"


def main() -> int:
    if not CREDENTIALS_PATH.exists():
        print(f"Error: Client credentials not found at {CREDENTIALS_PATH}")
        print()
        print("To set up:")
        print("1. Go to https://console.cloud.google.com/")
        print("2. Create a project (or select an existing one)")
        print("3. Enable the Google Docs API and Google Drive API")
        print("4. Go to APIs & Services > Credentials")
        print("5. Create an OAuth 2.0 Client ID (Desktop app type)")
        print("6. Download the JSON and save it to:")
        print(f"   {CREDENTIALS_PATH}")
        return 1

    # Check for existing valid token
    creds = None
    if TOKEN_PATH.exists():
        creds = Credentials.from_authorized_user_file(str(TOKEN_PATH), SCOPES)

    if creds and creds.valid:
        print(f"Already authenticated. Token at {TOKEN_PATH}")
        _print_user_info(creds)
        return 0

    if creds and creds.expired and creds.refresh_token:
        print("Token expired, refreshing...")
        creds.refresh(Request())
    else:
        print("Opening browser for Google sign-in...")
        flow = InstalledAppFlow.from_client_secrets_file(
            str(CREDENTIALS_PATH), SCOPES
        )
        creds = flow.run_local_server(port=0)

    # Save token
    TOKEN_PATH.parent.mkdir(parents=True, exist_ok=True)
    TOKEN_PATH.write_text(creds.to_json())
    print(f"Token saved to {TOKEN_PATH}")

    _print_user_info(creds)
    return 0


def _print_user_info(creds: Credentials) -> None:
    """Print the authenticated user's email."""
    try:
        service = build("oauth2", "v2", credentials=creds)
        user_info = service.userinfo().get().execute()
        print(f"Authenticated as: {user_info.get('email', 'unknown')}")
    except Exception:
        print("Authenticated successfully.")


if __name__ == "__main__":
    sys.exit(main())
