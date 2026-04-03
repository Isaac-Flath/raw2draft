#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""
Show project status.

Usage:
    uv run status.py [project_dir]
    uv run status.py --list

If no project specified, uses the most recently modified project.
"""

import argparse
import subprocess
import sys
from pathlib import Path


def find_linked_post(project_dir: Path) -> Path | None:
    """Find the linked post in posts/ for a project."""
    posts_dir = Path("posts")
    if not posts_dir.exists():
        return None

    parts = project_dir.name.split("_", 3)
    if len(parts) == 4:
        slug = parts[3]
        date_hyphen = f"{parts[0]}-{parts[1]}-{parts[2]}"
        candidate = posts_dir / f"{date_hyphen}-{slug}" / "blog.md"
        if candidate.exists():
            return candidate

    slug = parts[3] if len(parts) == 4 else project_dir.name
    for entry in posts_dir.iterdir():
        if entry.is_dir() and entry.name.endswith(slug):
            blog_md = entry / "blog.md"
            if blog_md.exists():
                return blog_md
    return None


def get_post_status(post_path: Path) -> tuple[bool, str]:
    """Check draft status and access level from frontmatter.

    Returns (is_draft, access_level) where access_level is 'public' or 'members'.
    """
    text = post_path.read_text()
    lines = text.split("\n")
    is_draft = False
    access = "public"
    if not lines or lines[0].strip() != "---":
        return False, access
    for line in lines[1:]:
        if line.strip() == "---":
            break
        if line.strip().startswith("draft:") and "true" in line.lower():
            is_draft = True
        if line.strip().startswith("access:") and "members" in line.lower():
            access = "members"
    return is_draft, access


def get_all_projects() -> list[Path]:
    projects_dir = Path("projects")
    if not projects_dir.exists():
        return []
    
    projects = sorted(projects_dir.iterdir(), key=lambda p: p.stat().st_mtime, reverse=True)
    return [p for p in projects if p.is_dir() and not p.name.startswith(".")]





def get_video_duration(video_path: Path) -> str | None:
    try:
        result = subprocess.run([
            "ffprobe", "-v", "error",
            "-show_entries", "format=duration",
            "-of", "default=noprint_wrappers=1:nokey=1",
            str(video_path)
        ], capture_output=True, text=True, timeout=10)
        
        if result.returncode == 0:
            seconds = float(result.stdout.strip())
            minutes = int(seconds // 60)
            secs = int(seconds % 60)
            return f"{minutes}:{secs:02d}"
    except (subprocess.TimeoutExpired, ValueError):
        pass
    return None


def count_words(file_path: Path) -> int:
    text = file_path.read_text()
    return len(text.split())


def format_words(count: int) -> str:
    if count >= 1000:
        return f"{count:,} words"
    return f"{count} words"


def check_file(path: Path, show_words: bool = False, show_duration: bool = False) -> tuple[bool, str]:
    if not path.exists():
        return False, "not generated"
    
    if show_duration and path.suffix in [".mp4", ".mov", ".webm", ".mkv"]:
        duration = get_video_duration(path)
        if duration:
            return True, duration
        return True, ""
    
    if show_words and path.suffix in [".md", ".txt"]:
        words = count_words(path)
        return True, format_words(words)
    
    return True, ""


def print_status(exists: bool, name: str, detail: str = ""):
    mark = "✓" if exists else "✗"
    if detail:
        print(f"  {mark} {name} ({detail})")
    else:
        print(f"  {mark} {name}")


def list_projects():
    projects = get_all_projects()
    if not projects:
        print("No projects found.")
        print("Run /content-init to create one.")
        return
    
    print("Projects (most recent first):\n")
    for i, p in enumerate(projects):
        name = p.name.split("_", 3)[-1].replace("-", " ").title()
        date = "_".join(p.name.split("_")[:3])
        marker = " <- latest" if i == 0 else ""
        print(f"  {p.name}{marker}")


def main():
    parser = argparse.ArgumentParser(description="Show project status")
    parser.add_argument("project", nargs="?", help="Project directory (required unless --list)")
    parser.add_argument("--list", "-l", action="store_true", help="List all projects")
    args = parser.parse_args()

    if args.list:
        list_projects()
        return

    if not args.project:
        print("Error: Project directory required.")
        print("\nUsage: status.py <project_dir>")
        print("       status.py --list")
        print("\nRun with --list to see available projects.")
        sys.exit(1)

    project_dir = Path(args.project)
    
    if not project_dir.exists():
        print("No project found.")
        print("Run /content-init to create one.")
        sys.exit(1)
    
    project_name = project_dir.name.split("_", 3)[-1].replace("-", " ").title()
    print(f"Project: {project_name}")
    print(f"Path: {project_dir}")
    print()
    
    source_dir = project_dir / "source"
    content_dir = project_dir / "content"
    social_dir = project_dir / "social"
    screenshots_dir = project_dir / "screenshots"
    
    # Source Materials
    print("Source Materials:")
    source_files = []
    if source_dir.exists():
        for f in sorted(source_dir.iterdir()):
            if f.is_file() and not f.name.startswith("."):
                source_files.append(f)
    
    if source_files:
        for f in source_files:
            exists, detail = check_file(f, show_words=True, show_duration=True)
            print_status(exists, f"source/{f.name}", detail)
    else:
        print("  (none)")
    print()
    
    # Blog Post (in posts/)
    print("Blog Post:")
    post_path = find_linked_post(project_dir)
    if post_path and post_path.exists():
        words = count_words(post_path)
        draft, access = get_post_status(post_path)
        status_parts = [format_words(words)]
        if draft:
            status_parts.append("draft")
        else:
            status_parts.append("published")
        if access == "members":
            status_parts.append("extras")
        print_status(True, f"posts/{post_path.parent.name}/{post_path.name}", ", ".join(status_parts))
    else:
        print_status(False, "posts/...", "not generated")

    # Transcript/description (still in project content/ if they exist)
    content_dir = project_dir / "content"
    for rel_path, show_words in [("content/transcript.md", True), ("content/description.md", False)]:
        path = project_dir / rel_path
        if path.exists():
            exists, detail = check_file(path, show_words=show_words)
            print_status(exists, rel_path, detail)
    print()
    
    # Social Media
    print("Social Media:")
    social_formats = [
        "text-xsmall.md",
        "text-small.md",
        "text-medium.md",
        "video-short.md",
        "video-medium.md",
        "video-long.md",
        "carousel.md",
    ]
    
    for filename in social_formats:
        path = social_dir / filename
        exists, _ = check_file(path)
        print_status(exists, f"social/{filename}")
    print()
    
    # Screenshots
    screenshot_count = 0
    if screenshots_dir.exists():
        screenshot_count = len([f for f in screenshots_dir.iterdir() if f.suffix in [".png", ".jpg"]])
    
    print(f"Screenshots: {screenshot_count} files")


if __name__ == "__main__":
    main()
