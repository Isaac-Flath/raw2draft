#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///

"""
Render a Remotion video project.

Usage:
    uv run .claude/skills/content-video/scripts/render_video.py <project-dir>

Runs `npx remotion render` in the project's video/ directory.
Output: video/out/final.mp4
"""

import subprocess
import sys
from pathlib import Path


def main():
    if len(sys.argv) < 2:
        print("Usage: uv run .claude/skills/content-video/scripts/render_video.py <project-dir>")
        sys.exit(1)

    project_dir = Path(sys.argv[1]).resolve()
    video_dir = project_dir / "video"

    if not video_dir.exists():
        print(f"Error: No video/ directory found in {project_dir}")
        print("Run setup_remotion.py first.")
        sys.exit(1)

    if not (video_dir / "node_modules").exists():
        print("Installing dependencies...")
        subprocess.run(
            ["npm", "install"],
            cwd=str(video_dir),
            timeout=120,
        )

    out_dir = video_dir / "out"
    out_dir.mkdir(parents=True, exist_ok=True)
    output_file = out_dir / "final.mp4"

    print("Rendering video...")
    print(f"Output: {output_file}")

    result = subprocess.run(
        [
            "npx", "remotion", "render",
            "src/index.ts",
            "main",
            str(output_file),
            "--codec", "h264",
        ],
        cwd=str(video_dir),
        timeout=600,
    )

    if result.returncode != 0:
        print("Error: Render failed.")
        sys.exit(1)

    if output_file.exists():
        size_mb = output_file.stat().st_size / (1024 * 1024)
        print(f"\nDone! Output: {output_file} ({size_mb:.1f} MB)")
    else:
        print("Error: Output file was not created.")
        sys.exit(1)


if __name__ == "__main__":
    main()
