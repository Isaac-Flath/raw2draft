"""Phase 2: Gather visual assets for confirmed mentions.

For each mention in the reviewed mentions file, fetch appropriate visual assets:
- Blog posts: screenshot via Playwright or OG image
- Talks: YouTube/conference thumbnail
- Tools: logo or homepage screenshot
- URLs: OG image or screenshot

Input: <stem>_mentions.json (reviewed/confirmed by user)
Output: screenshots/images in claude-edits/overlays/assets/
"""

import json
import os
import re
import sys
from pathlib import Path
from urllib.parse import urlparse

import requests
from bs4 import BeautifulSoup


def fetch_og_metadata(url):
    """Fetch Open Graph metadata from a URL."""
    try:
        resp = requests.get(url, timeout=10, headers={
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"
        })
        resp.raise_for_status()
        soup = BeautifulSoup(resp.text, "html.parser")

        og = {}
        for tag in soup.find_all("meta"):
            prop = tag.get("property", "") or tag.get("name", "")
            if prop.startswith("og:"):
                og[prop[3:]] = tag.get("content", "")
            elif prop == "twitter:image":
                og.setdefault("image", tag.get("content", ""))

        # Fallback to title tag
        if "title" not in og:
            title_tag = soup.find("title")
            if title_tag:
                og["title"] = title_tag.text.strip()

        return og
    except Exception as e:
        print(f"  Warning: could not fetch OG data from {url}: {e}")
        return {}


def download_image(url, output_path):
    """Download an image from a URL."""
    try:
        resp = requests.get(url, timeout=15, headers={
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"
        })
        resp.raise_for_status()
        content_type = resp.headers.get("content-type", "")
        if "image" not in content_type and "octet-stream" not in content_type:
            print(f"  Warning: {url} returned content-type {content_type}, skipping")
            return False
        os.makedirs(os.path.dirname(output_path), exist_ok=True)
        with open(output_path, "wb") as f:
            f.write(resp.content)
        return True
    except Exception as e:
        print(f"  Warning: could not download {url}: {e}")
        return False


def screenshot_url(url, output_path, width=1280, height=800):
    """Take a screenshot of a URL using Playwright."""
    try:
        from playwright.sync_api import sync_playwright
    except ImportError:
        print("  Warning: playwright not available, skipping screenshot")
        return False

    try:
        os.makedirs(os.path.dirname(output_path), exist_ok=True)
        with sync_playwright() as p:
            browser = p.chromium.launch(headless=True)
            page = browser.new_page(viewport={"width": width, "height": height})
            page.goto(url, wait_until="networkidle", timeout=15000)
            page.screenshot(path=output_path, type="png")
            browser.close()
        return True
    except Exception as e:
        print(f"  Warning: screenshot failed for {url}: {e}")
        return False


def fetch_youtube_thumbnail(url):
    """Extract YouTube video ID and return thumbnail URL."""
    patterns = [
        r"(?:youtube\.com/watch\?v=|youtu\.be/|youtube\.com/embed/)([a-zA-Z0-9_-]{11})",
    ]
    for pattern in patterns:
        m = re.search(pattern, url)
        if m:
            video_id = m.group(1)
            # maxresdefault is highest quality, falls back to hqdefault
            return f"https://img.youtube.com/vi/{video_id}/maxresdefault.jpg"
    return None


def gather_asset_for_mention(mention, assets_dir):
    """Gather the visual asset for a single mention.

    Returns updated mention dict with asset_path and metadata.
    """
    mention_id = mention["id"]
    mention_type = mention["type"]
    url = mention.get("url")
    asset_path = os.path.join(assets_dir, f"{mention_id}.png")

    metadata = mention.get("metadata", {})

    if mention_type in ("blog-card", "url-callout", "tool", "generic-image"):
        if url:
            # Try OG metadata first
            og = fetch_og_metadata(url)
            metadata.update({
                "og_title": og.get("title", mention.get("label", "")),
                "og_description": og.get("description", ""),
                "og_image": og.get("image", ""),
                "domain": urlparse(url).netloc,
            })

            # Try OG image first (lighter weight)
            if og.get("image"):
                if download_image(og["image"], asset_path):
                    mention["asset_path"] = asset_path
                    mention["metadata"] = metadata
                    return mention

            # Fall back to screenshot
            if screenshot_url(url, asset_path):
                mention["asset_path"] = asset_path
                mention["metadata"] = metadata
                return mention

    elif mention_type == "talk-thumbnail":
        if url:
            # Check for YouTube URL
            thumb_url = fetch_youtube_thumbnail(url)
            if thumb_url:
                jpg_path = os.path.join(assets_dir, f"{mention_id}.jpg")
                if download_image(thumb_url, jpg_path):
                    mention["asset_path"] = jpg_path
                    mention["metadata"] = metadata
                    return mention

            # Try OG image
            og = fetch_og_metadata(url)
            metadata.update({
                "og_title": og.get("title", mention.get("label", "")),
                "og_description": og.get("description", ""),
                "domain": urlparse(url).netloc,
            })
            if og.get("image"):
                if download_image(og["image"], asset_path):
                    mention["asset_path"] = asset_path
                    mention["metadata"] = metadata
                    return mention

    elif mention_type == "key-term":
        # No asset needed for key terms — rendered as text
        mention["metadata"] = metadata
        return mention

    # If we get here, no asset was fetched
    mention["metadata"] = metadata
    return mention


def gather_assets(mentions_data, output_dir):
    """Gather assets for all confirmed mentions.

    Args:
        mentions_data: Parsed mentions JSON
        output_dir: Base output directory (claude-edits/)

    Returns:
        Updated mentions_data with asset_path and metadata filled in
    """
    assets_dir = os.path.join(output_dir, "overlays", "assets")
    os.makedirs(assets_dir, exist_ok=True)

    mentions = mentions_data.get("mentions", [])
    print(f"Gathering assets for {len(mentions)} mentions...")

    for i, mention in enumerate(mentions):
        print(f"\n  [{i + 1}/{len(mentions)}] {mention['type']}: {mention['label']}")
        mention = gather_asset_for_mention(mention, assets_dir)
        mentions[i] = mention

        if mention.get("asset_path"):
            print(f"    Asset: {mention['asset_path']}")
        else:
            print(f"    No asset (will render as text-only overlay)")

    mentions_data["mentions"] = mentions
    return mentions_data


# ── CLI ──────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: uv run gather_assets.py <mentions_json> [--output-dir <dir>]")
        sys.exit(1)

    mentions_path = sys.argv[1]
    output_dir = None

    args = sys.argv[2:]
    i = 0
    while i < len(args):
        if args[i] == "--output-dir" and i + 1 < len(args):
            output_dir = args[i + 1]
            i += 2
        else:
            i += 1

    with open(mentions_path) as f:
        mentions_data = json.load(f)

    if output_dir is None:
        output_dir = os.path.dirname(os.path.abspath(mentions_path))

    mentions_data = gather_assets(mentions_data, output_dir)

    # Save updated mentions with asset paths
    with open(mentions_path, "w") as f:
        json.dump(mentions_data, f, indent=2)
    print(f"\nUpdated mentions saved to {mentions_path}")
