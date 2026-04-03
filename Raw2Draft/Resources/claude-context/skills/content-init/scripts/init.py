#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""
Initialize a new content project.

Usage:
    uv run init.py "<title>"

Creates:
    - posts/YYYY-MM-DD-<slug>/ (post directory with blog.md and working subdirectories)
"""

import re
import sys
from datetime import datetime
from pathlib import Path


def slugify(title: str) -> str:
    """Convert title to URL-friendly slug."""
    slug = title.lower()
    slug = re.sub(r'[^\w\s-]', '', slug)
    slug = re.sub(r'[\s_]+', '-', slug)
    slug = re.sub(r'-+', '-', slug)
    return slug.strip('-')


def main():
    if len(sys.argv) < 2:
        print("Usage: init.py <title>")
        print("\nExample:")
        print('  init.py "My Blog Post Title"')
        sys.exit(1)

    title = sys.argv[1]
    slug = slugify(title)
    now = datetime.now()
    date_hyphen = now.strftime("%Y-%m-%d")

    post_dir = Path("posts") / f"{date_hyphen}-{slug}"

    if post_dir.exists():
        print(f"Error: Post directory already exists: {post_dir}")
        sys.exit(1)

    # Create post directory with working subdirectories
    post_dir.mkdir(parents=True)
    (post_dir / "source").mkdir()
    (post_dir / "screenshots").mkdir()
    (post_dir / "social").mkdir()
    (post_dir / "images").mkdir()
    (post_dir / "video").mkdir()

    # Create draft blog post
    blog_path = post_dir / "blog.md"
    blog_path.write_text(f"""---
title: "{title}"
description: ""
author: "Isaac Flath"
date: "{date_hyphen}"
draft: true
section: ""
subsection: ""
access: public
---

""")

    print(f"Created: {post_dir}/")
    print(f"  blog.md        (draft)")
    print(f"  source/        # Add raw materials here")
    print(f"  screenshots/")
    print(f"  social/")
    print(f"  images/")
    print(f"  video/")
    print(f"\nNext: Add source content or run /content-youtube <url>")


if __name__ == "__main__":
    main()
