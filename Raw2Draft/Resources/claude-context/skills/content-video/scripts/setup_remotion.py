#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.11"
# dependencies = ["jinja2"]
# ///

"""
Set up a Remotion project from project assets.

Usage:
    uv run .claude/skills/content-video/scripts/setup_remotion.py <project-dir>

Discovers source videos, images, screenshots, and blog content,
then scaffolds a Remotion project in <project-dir>/video/.
"""

import json
import os
import subprocess
import sys
from pathlib import Path

from jinja2 import Environment, FileSystemLoader

VIDEO_EXTENSIONS = {".mp4", ".mov", ".webm"}
IMAGE_EXTENSIONS = {".png", ".jpg", ".jpeg", ".gif", ".webp"}

PACKAGE_JSON = {
    "name": "raw2draft-video",
    "version": "1.0.0",
    "private": True,
    "scripts": {
        "preview": "remotion preview src/index.ts",
        "render": "remotion render src/index.ts main out/final.mp4 --codec h264",
    },
    "dependencies": {
        "@remotion/cli": "^4.0.0",
        "react": "^18.2.0",
        "react-dom": "^18.2.0",
        "remotion": "^4.0.0",
        "typescript": "^5.0.0",
    },
}

TSCONFIG = {
    "compilerOptions": {
        "target": "ES2022",
        "module": "ES2022",
        "moduleResolution": "bundler",
        "jsx": "react-jsx",
        "strict": True,
        "esModuleInterop": True,
        "skipLibCheck": True,
        "outDir": "dist",
    },
    "include": ["src"],
}


def find_files(directory: Path, extensions: set[str]) -> list[str]:
    """Find files with given extensions in a directory."""
    if not directory.exists():
        return []
    return sorted(
        f.name
        for f in directory.iterdir()
        if f.is_file() and f.suffix.lower() in extensions
    )


def get_video_duration(video_path: Path) -> float:
    """Get video duration in seconds using ffprobe."""
    try:
        result = subprocess.run(
            [
                "ffprobe",
                "-v", "quiet",
                "-print_format", "json",
                "-show_format",
                str(video_path),
            ],
            capture_output=True,
            text=True,
            timeout=30,
        )
        if result.returncode == 0:
            data = json.loads(result.stdout)
            return float(data.get("format", {}).get("duration", 60))
    except (subprocess.TimeoutExpired, json.JSONDecodeError, FileNotFoundError):
        pass
    return 60.0  # Default fallback


def read_blog_excerpt(content_dir: Path, max_lines: int = 10) -> list[str]:
    """Read first N non-empty lines from blog.md for text overlays."""
    blog = content_dir / "blog.md"
    if not blog.exists():
        return []
    lines = []
    for line in blog.read_text().splitlines():
        stripped = line.strip()
        if stripped and not stripped.startswith("#") and not stripped.startswith("!["):
            lines.append(stripped)
            if len(lines) >= max_lines:
                break
    return lines


def main():
    if len(sys.argv) < 2:
        print("Usage: uv run .claude/skills/content-video/scripts/setup_remotion.py <project-dir>")
        sys.exit(1)

    project_dir = Path(sys.argv[1]).resolve()
    if not project_dir.exists():
        print(f"Error: Project directory not found: {project_dir}")
        sys.exit(1)

    source_dir = project_dir / "source"
    images_dir = project_dir / "images"
    screenshots_dir = project_dir / "screenshots"
    content_dir = project_dir / "content"
    video_dir = project_dir / "video"

    # Discover assets
    source_videos = find_files(source_dir, VIDEO_EXTENSIONS)
    images = find_files(images_dir, IMAGE_EXTENSIONS)
    screenshots = find_files(screenshots_dir, IMAGE_EXTENSIONS)
    blog_lines = read_blog_excerpt(content_dir)

    print(f"Found {len(source_videos)} source video(s)")
    print(f"Found {len(images)} image(s)")
    print(f"Found {len(screenshots)} screenshot(s)")
    print(f"Found {len(blog_lines)} blog excerpt line(s)")

    if not source_videos and not images and not screenshots:
        print("\nWarning: No assets found. Add source videos or run /content-image first.")

    if not images and not screenshots:
        print("\nTip: Run /content-image or /content-screenshot to generate overlay images.")

    # Get duration of first source video
    duration_seconds = 60.0
    if source_videos:
        first_video = source_dir / source_videos[0]
        duration_seconds = get_video_duration(first_video)
        print(f"Source video duration: {duration_seconds:.1f}s")

    fps = 30
    total_frames = int(duration_seconds * fps)

    # Create video directory structure
    video_src = video_dir / "src"
    video_public = video_dir / "public"
    video_out = video_dir / "out"

    for d in [video_src, video_public, video_out]:
        d.mkdir(parents=True, exist_ok=True)

    # Write package.json and tsconfig.json
    (video_dir / "package.json").write_text(json.dumps(PACKAGE_JSON, indent=2))
    (video_dir / "tsconfig.json").write_text(json.dumps(TSCONFIG, indent=2))
    print("Created package.json and tsconfig.json")

    # Symlink assets into public/
    def symlink_dir(src: Path, dest_name: str):
        dest = video_public / dest_name
        if dest.exists() or dest.is_symlink():
            dest.unlink() if dest.is_symlink() else None
        if src.exists():
            dest.symlink_to(src.resolve())
            print(f"Linked {dest_name}/ -> {src}")

    symlink_dir(source_dir, "source")
    symlink_dir(images_dir, "images")
    symlink_dir(screenshots_dir, "screenshots")

    # Render templates
    templates_dir = Path(__file__).parent.parent / "templates"
    env = Environment(loader=FileSystemLoader(str(templates_dir)))

    template_context = {
        "source_videos": source_videos,
        "images": images,
        "screenshots": screenshots,
        "blog_lines": blog_lines,
        "duration_seconds": duration_seconds,
        "fps": fps,
        "total_frames": total_frames,
        "width": 1920,
        "height": 1080,
    }

    for template_name, output_path in [
        ("index.ts.jinja2", video_src / "index.ts"),
        ("Root.tsx.jinja2", video_src / "Root.tsx"),
        ("Composition.tsx.jinja2", video_src / "Composition.tsx"),
    ]:
        template = env.get_template(template_name)
        output_path.write_text(template.render(**template_context))
        print(f"Generated {output_path.relative_to(video_dir)}")

    # Install dependencies
    print("\nInstalling npm dependencies...")
    result = subprocess.run(
        ["npm", "install"],
        cwd=str(video_dir),
        capture_output=True,
        text=True,
        timeout=120,
    )
    if result.returncode != 0:
        print(f"Warning: npm install failed:\n{result.stderr}")
    else:
        print("Dependencies installed successfully.")

    print(f"\nReady! Preview with: cd {video_dir} && npx remotion preview")
    print(f"Render with: uv run .claude/skills/content-video/scripts/render_video.py {project_dir}")


if __name__ == "__main__":
    main()
