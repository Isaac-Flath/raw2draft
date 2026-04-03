#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""
Extract screenshots from video at specific timestamps.

Usage:
    uv run screenshot.py <video_path> <output_dir> <timestamp1> [timestamp2] ...

Timestamp formats:
    1:30 or 01:30   -> 1 minute 30 seconds
    1:30:45         -> 1 hour 30 minutes 45 seconds
    90 or 90s       -> 90 seconds

Requires:
    - ffmpeg
"""

import re
import subprocess
import sys
from pathlib import Path


def parse_timestamp(ts: str) -> int:
    """Parse timestamp string to seconds."""
    ts = ts.strip().lower().rstrip('s')

    # Pure number (seconds)
    if ts.isdigit():
        return int(ts)

    # HH:MM:SS or MM:SS
    parts = ts.split(':')
    if len(parts) == 2:
        minutes, seconds = int(parts[0]), int(parts[1])
        return minutes * 60 + seconds
    elif len(parts) == 3:
        hours, minutes, seconds = int(parts[0]), int(parts[1]), int(parts[2])
        return hours * 3600 + minutes * 60 + seconds

    raise ValueError(f"Invalid timestamp format: {ts}")


def format_timestamp(seconds: int) -> str:
    """Format seconds as MMmSSs for filename."""
    minutes = seconds // 60
    secs = seconds % 60
    return f"{minutes:02d}m{secs:02d}s"


def format_ffmpeg_timestamp(seconds: int) -> str:
    """Format seconds as HH:MM:SS for ffmpeg."""
    hours = seconds // 3600
    minutes = (seconds % 3600) // 60
    secs = seconds % 60
    return f"{hours:02d}:{minutes:02d}:{secs:02d}"


def extract_screenshot(video_path: Path, output_dir: Path, timestamp_seconds: int) -> Path | None:
    """Extract a single screenshot at the given timestamp."""
    timestamp_str = format_timestamp(timestamp_seconds)
    output_path = output_dir / f"screenshot-{timestamp_str}.png"

    ffmpeg_ts = format_ffmpeg_timestamp(timestamp_seconds)

    result = subprocess.run([
        "ffmpeg", "-y",
        "-ss", ffmpeg_ts,
        "-i", str(video_path),
        "-vframes", "1",
        "-q:v", "2",
        str(output_path)
    ], capture_output=True, text=True)

    if result.returncode != 0:
        print(f"  Error at {ffmpeg_ts}: {result.stderr.strip()}")
        return None

    return output_path


def main():
    if len(sys.argv) < 4:
        print("Usage: screenshot.py <video_path> <output_dir> <timestamp1> [timestamp2] ...")
        print("\nTimestamp formats:")
        print("  1:30 or 01:30  -> 1 minute 30 seconds")
        print("  1:30:45        -> 1 hour 30 minutes 45 seconds")
        print("  90 or 90s      -> 90 seconds")
        print("\nExample:")
        print("  screenshot.py source/video.mp4 screenshots 0:45 2:15 5:30")
        sys.exit(1)

    video_path = Path(sys.argv[1])
    output_dir = Path(sys.argv[2])
    timestamps = sys.argv[3:]

    if not video_path.exists():
        print(f"Video not found: {video_path}")
        sys.exit(1)

    output_dir.mkdir(parents=True, exist_ok=True)

    print(f"Extracting {len(timestamps)} screenshot(s) from: {video_path.name}")

    extracted = []
    for ts in timestamps:
        try:
            seconds = parse_timestamp(ts)
            print(f"  {ts} -> {format_timestamp(seconds)}...", end=" ")

            result = extract_screenshot(video_path, output_dir, seconds)
            if result:
                print("done")
                extracted.append(result.name)
            else:
                print("failed")
        except ValueError as e:
            print(f"  Skipping invalid timestamp: {ts}")

    if extracted:
        print(f"\nExtracted {len(extracted)} screenshot(s) to {output_dir}/")
        for name in extracted:
            print(f"  - {name}")


if __name__ == "__main__":
    main()
