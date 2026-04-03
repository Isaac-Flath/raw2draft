# /// script
# requires-python = ">=3.11"
# dependencies = ["boto3"]
# ///
"""Upload local images referenced in a blog post to S3 and replace paths with URLs.

Usage:
    uv run publish_prep.py <post-path-or-project-dir>

If given a project directory, finds the linked post in posts/.
If given a .md file path, uses that directly.
"""

import mimetypes
import os
import re
import secrets
import sys
from pathlib import Path


def get_app_root() -> Path:
    """Get the monorepo root."""
    return Path(__file__).resolve().parent.parent.parent.parent.parent


def find_post_for_project(project_dir: Path) -> Path | None:
    """Find the linked post in posts/ for a project directory."""
    app_root = get_app_root()
    posts_dir = app_root / "posts"

    parts = project_dir.name.split("_", 3)
    if len(parts) == 4:
        slug = parts[3]
        date_hyphen = f"{parts[0]}-{parts[1]}-{parts[2]}"
        candidate = posts_dir / f"{date_hyphen}-{slug}" / "blog.md"
        if candidate.exists():
            return candidate

    # Fallback: search by slug
    slug = parts[3] if len(parts) == 4 else project_dir.name
    for entry in posts_dir.iterdir():
        if entry.is_dir() and entry.name.endswith(slug):
            blog_md = entry / "blog.md"
            if blog_md.exists():
                return blog_md

    return None


def get_s3_client():
    return boto3.client(
        "s3",
        aws_access_key_id=os.environ["AWS_ACCESS_KEY_ID"],
        aws_secret_access_key=os.environ["AWS_SECRET_ACCESS_KEY"],
        region_name=os.environ["AWS_REGION"],
    )


def upload_file(s3, bucket: str, region: str, file_path: Path) -> str:
    ext = file_path.suffix.lstrip(".")
    key = f"{secrets.token_hex(16)}.{ext}"
    content_type = mimetypes.guess_type(str(file_path))[0] or "application/octet-stream"

    s3.upload_file(
        str(file_path),
        bucket,
        key,
        ExtraArgs={"ContentType": content_type},
    )

    return f"https://{bucket}.s3.{region}.amazonaws.com/{key}"


def main():
    import boto3

    target = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(".")
    target = target.resolve()

    # Determine the post file and the base directory for resolving image paths
    if target.suffix == ".md":
        blog_path = target
        # Image paths in the post are relative to the project dir or monorepo root
        base_dir = get_app_root()
    elif target.is_dir():
        blog_path = find_post_for_project(target)
        if not blog_path:
            print(f"Error: No linked post found for project {target.name}", file=sys.stderr)
            sys.exit(1)
        base_dir = target  # Resolve image paths relative to project dir
    else:
        print(f"Error: {target} is not a .md file or directory", file=sys.stderr)
        sys.exit(1)

    if not blog_path.exists():
        print(f"Error: {blog_path} not found", file=sys.stderr)
        sys.exit(1)

    print(f"Post: {blog_path}")
    print(f"Base: {base_dir}")

    for var in ("AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_REGION", "S3_BUCKET"):
        if var not in os.environ:
            print(f"Error: {var} environment variable not set", file=sys.stderr)
            sys.exit(1)

    bucket = os.environ["S3_BUCKET"]
    region = os.environ["AWS_REGION"]
    s3 = get_s3_client()

    content = blog_path.read_text()
    image_pattern = re.compile(r"(!\[[^\]]*\])\(([^)]+)\)")

    uploaded = 0
    skipped = 0

    def replace_image(match):
        nonlocal uploaded, skipped
        alt_part = match.group(1)
        path_str = match.group(2)

        # Skip URLs
        if path_str.startswith(("http://", "https://")):
            skipped += 1
            return match.group(0)

        file_path = (base_dir / path_str).resolve()
        if not file_path.exists():
            print(f"  Warning: {path_str} not found, skipping")
            skipped += 1
            return match.group(0)

        url = upload_file(s3, bucket, region, file_path)
        print(f"  Uploaded: {path_str} -> {url}")
        uploaded += 1
        return f"{alt_part}({url})"

    new_content = image_pattern.sub(replace_image, content)
    blog_path.write_text(new_content)

    print(f"\nDone: {uploaded} uploaded, {skipped} skipped")


if __name__ == "__main__":
    main()
