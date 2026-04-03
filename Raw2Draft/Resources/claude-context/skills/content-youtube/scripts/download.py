#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Download YouTube videos using yt-dlp with robust error handling.

Requires yt-dlp CLI: brew install yt-dlp
"""

import argparse
import re
import subprocess
import sys
from pathlib import Path


def sanitize_filename(title: str) -> str:
    """Sanitize a string for use as a filename."""
    # Remove or replace problematic characters
    sanitized = re.sub(r'[<>:"/\\|?*]', '', title)
    sanitized = re.sub(r'\s+', ' ', sanitized).strip()
    # Truncate if too long
    if len(sanitized) > 200:
        sanitized = sanitized[:200]
    return sanitized


def get_video_title(url: str) -> str | None:
    """Get the video title from YouTube."""
    cmd = ["yt-dlp", "--get-title", "--no-playlist", url]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        if result.returncode == 0:
            return result.stdout.strip()
    except subprocess.TimeoutExpired:
        pass
    return None


def download_video(
    url: str,
    output_dir: Path,
    max_size_mb: int = 500,
    audio_only: bool = False,
) -> Path:
    """
    Download a YouTube video using yt-dlp.

    Args:
        url: YouTube video URL
        output_dir: Directory to save the video
        max_size_mb: Maximum file size in MB
        audio_only: If True, download audio only as mp3

    Returns:
        Path to the downloaded file

    Raises:
        ValueError: If download fails
    """
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    # Get video title for filename
    title = get_video_title(url)
    if title:
        safe_title = sanitize_filename(title)
    else:
        safe_title = "video"

    if audio_only:
        ext = "mp3"
        output_path = output_dir / f"{safe_title}.{ext}"
        format_spec = "bestaudio/best"
        extra_args = [
            "--extract-audio",
            "--audio-format", "mp3",
            "--audio-quality", "0",
        ]
    else:
        ext = "mp4"
        output_path = output_dir / f"{safe_title}.{ext}"
        format_spec = "best[ext=mp4]/best"
        extra_args = []

    # Handle filename conflicts
    counter = 1
    original_stem = output_path.stem
    while output_path.exists():
        output_path = output_dir / f"{original_stem} ({counter}).{ext}"
        counter += 1

    cmd = [
        "yt-dlp",
        "-f", format_spec,
        "-o", str(output_path),
        "--no-playlist",
        "--max-filesize", f"{max_size_mb}M",
        "--no-warnings",
        "--progress",
        *extra_args,
        url,
    ]

    print(f"Downloading: {title or url}")
    print(f"Output: {output_path}")

    try:
        process = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=600,  # 10 minute timeout
        )
    except subprocess.TimeoutExpired:
        raise ValueError("Download timed out after 10 minutes")

    if process.returncode != 0:
        error_msg = process.stderr or process.stdout or "Unknown error"

        if "Video unavailable" in error_msg:
            raise ValueError("Video is unavailable or private")
        if "Private video" in error_msg:
            raise ValueError("Video is private")
        if "Sign in" in error_msg:
            raise ValueError("Video requires sign-in (age-restricted or private)")
        if "max-filesize" in error_msg.lower() or "File is larger" in error_msg:
            raise ValueError(f"Video exceeds {max_size_mb}MB size limit")
        if "HTTP Error 403" in error_msg:
            raise ValueError("Access forbidden - video may be geo-restricted")
        if "HTTP Error 404" in error_msg:
            raise ValueError("Video not found")

        # Truncate long error messages
        error_snippet = error_msg[:300] if len(error_msg) > 300 else error_msg
        raise ValueError(f"Download failed: {error_snippet}")

    # Verify file was created
    # yt-dlp might add extension or modify filename slightly
    if not output_path.exists():
        # Search for files that match the pattern
        pattern = f"{original_stem}*"
        matches = list(output_dir.glob(pattern))
        if matches:
            output_path = matches[0]
        else:
            raise ValueError("Download appeared to succeed but no file was created")

    print(f"Downloaded: {output_path}")
    return output_path


def main():
    parser = argparse.ArgumentParser(
        description="Download YouTube videos using yt-dlp"
    )
    parser.add_argument("url", help="YouTube video URL")
    parser.add_argument(
        "output_dir",
        nargs="?",
        default="source",
        help="Output directory (default: source/)"
    )
    parser.add_argument(
        "--max-size",
        type=int,
        default=500,
        help="Maximum file size in MB (default: 500)"
    )
    parser.add_argument(
        "--audio-only",
        action="store_true",
        help="Download audio only as mp3"
    )

    args = parser.parse_args()

    try:
        output_path = download_video(
            url=args.url,
            output_dir=Path(args.output_dir),
            max_size_mb=args.max_size,
            audio_only=args.audio_only,
        )
        print(f"\nSuccess: {output_path}")
        return 0
    except ValueError as e:
        print(f"\nError: {e}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("\nDownload cancelled", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
