#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "python-dotenv",
#     "jinja2",
# ]
# ///
"""
Blog generation using gemini-3 skill for multimodal content.

Usage:
    uv run generate_blog.py <project_dir> [--model MODEL]
"""

import argparse
import subprocess
import sys
from pathlib import Path

from dotenv import load_dotenv
from jinja2 import Environment, FileSystemLoader, select_autoescape

load_dotenv()


def load_text_file(path: Path) -> str | None:
    """Load a text file if it exists."""
    if path.exists():
        return path.read_text()
    return None


def get_skills_root() -> Path:
    """Get the skills directory root (.claude/skills/)."""
    # Script is at: .claude/skills/content-blog/scripts/generate_blog.py
    # Skills root is: .claude/skills/
    return Path(__file__).resolve().parent.parent.parent


def get_app_root() -> Path:
    """Get the app root directory."""
    # Skills root is at: .claude/skills/
    # App root is: .
    return get_skills_root().parent.parent


def get_templates_dir() -> Path:
    """Get the templates directory path."""
    script_dir = Path(__file__).parent.parent
    return script_dir / "templates"


def load_writing_style() -> str:
    """Load the shared writing style guide."""
    app_root = get_app_root()
    style_path = app_root / "references" / "writing-style.md"
    if style_path.exists():
        return style_path.read_text()

    # Fallback to skill-specific if shared doesn't exist
    script_dir = Path(__file__).parent.parent
    style_path = script_dir / "references" / "writing-style.md"
    if style_path.exists():
        return style_path.read_text()

    return "# Writing Style\n\nWrite clearly and concisely."


def gather_sources(project_dir: Path) -> dict:
    """Gather all source materials from the project."""
    content_dir = project_dir / "content"
    source_dir = project_dir / "source"
    screenshots_dir = project_dir / "screenshots"

    sources = {
        "transcript": None,
        "chapters": None,
        "image_paths": [],
        "pdf_paths": [],
        "text_files": [],
    }

    # Load transcript
    transcript_path = content_dir / "transcript.md"
    sources["transcript"] = load_text_file(transcript_path)

    # Load chapters/description if exists
    chapters_path = content_dir / "description.md"
    sources["chapters"] = load_text_file(chapters_path)

    # Load screenshots
    if screenshots_dir.exists():
        for img_path in sorted(screenshots_dir.glob("*.png")):
            sources["image_paths"].append(img_path)
        for img_path in sorted(screenshots_dir.glob("*.jpg")):
            sources["image_paths"].append(img_path)

    # Load source directory files
    if source_dir.exists():
        for ext in ["*.png", "*.jpg", "*.jpeg", "*.gif", "*.webp"]:
            for img_path in sorted(source_dir.glob(ext)):
                sources["image_paths"].append(img_path)

        for pdf_path in sorted(source_dir.glob("*.pdf")):
            sources["pdf_paths"].append(pdf_path)

        for ext in ["*.txt", "*.md"]:
            for txt_path in sorted(source_dir.glob(ext)):
                content = load_text_file(txt_path)
                if content:
                    sources["text_files"].append(
                        {"path": f"source/{txt_path.name}", "content": content}
                    )

    return sources


def build_prompt(sources: dict) -> str:
    """Build the generation prompt from sources using Jinja2 templates."""
    templates_dir = get_templates_dir()

    # Set up Jinja2 environment
    env = Environment(
        loader=FileSystemLoader(templates_dir),
        autoescape=select_autoescape(),
        trim_blocks=True,
        lstrip_blocks=True,
    )

    # Load the main template
    template = env.get_template("blog_post.jinja2")

    # Prepare context (without actual image/pdf data, just metadata)
    context = {
        "writing_style": load_writing_style(),
        "transcript": sources["transcript"],
        "chapters": sources["chapters"],
        "text_files": sources["text_files"],
        "images": [{"path": str(p.name)} for p in sources["image_paths"]],
        "pdfs": [{"path": str(p.name)} for p in sources["pdf_paths"]],
    }

    # Render the template
    return template.render(**context)


def generate_blog(
    sources: dict,
    model_name: str = "gemini-2.5-pro",
) -> str:
    """Generate blog post using the gemini-3 skill."""
    skills_root = get_skills_root()

    # Build the prompt
    prompt = build_prompt(sources)

    # Build command to call gemini-3 skill (sibling skill in same skills directory)
    skill_script = skills_root / "gemini-3" / "scripts" / "query.py"
    if not skill_script.exists():
        print(f"Error: gemini-3 skill not found at {skill_script}", file=sys.stderr)
        sys.exit(1)

    cmd = ["uv", "run", str(skill_script), prompt, "--model", model_name]

    # Add all file arguments
    for img_path in sources["image_paths"]:
        cmd.extend(["--file", str(img_path)])

    for pdf_path in sources["pdf_paths"]:
        cmd.extend(["--file", str(pdf_path)])

    print(f"Generating blog post with gemini-3 ({model_name})...")
    print(f"  - Transcript: {'Yes' if sources['transcript'] else 'No'}")
    print(f"  - Images: {len(sources['image_paths'])}")
    print(f"  - PDFs: {len(sources['pdf_paths'])}")
    print(f"  - Text files: {len(sources['text_files'])}")

    # Run the gemini-3 skill
    result = subprocess.run(cmd, capture_output=True, text=True)

    if result.returncode != 0:
        print("\nError calling gemini-3:", file=sys.stderr)
        print(result.stderr, file=sys.stderr)
        sys.exit(1)

    return result.stdout


def find_post_path(project_dir: Path) -> Path:
    """Find the linked post in posts/ for this project."""
    app_root = get_app_root()
    posts_dir = app_root / "posts"

    # Extract slug from project dir name (YYYY_MM_DD_slug -> slug)
    parts = project_dir.name.split("_", 3)
    if len(parts) == 4:
        slug = parts[3]
        date_hyphen = f"{parts[0]}-{parts[1]}-{parts[2]}"
    else:
        slug = project_dir.name
        date_hyphen = ""

    # Search for matching post directory
    if date_hyphen:
        candidate = posts_dir / f"{date_hyphen}-{slug}" / "blog.md"
        if candidate.exists():
            return candidate

    # Fallback: search by slug suffix
    for entry in posts_dir.iterdir():
        if entry.is_dir() and entry.name.endswith(slug):
            blog_md = entry / "blog.md"
            if blog_md.exists():
                return blog_md

    # No existing post found — create new directory
    if date_hyphen:
        new_dir = posts_dir / f"{date_hyphen}-{slug}"
        new_dir.mkdir(exist_ok=True)
        return new_dir / "blog.md"

    from datetime import datetime
    date_str = datetime.now().strftime("%Y-%m-%d")
    new_dir = posts_dir / f"{date_str}-{slug}"
    new_dir.mkdir(exist_ok=True)
    return new_dir / "blog.md"


def main():
    parser = argparse.ArgumentParser(description="Generate blog post using gemini-3")
    parser.add_argument("project_dir", nargs="?", default=".", help="Project directory")
    parser.add_argument("--model", default="gemini-2.5-pro", help="Gemini model to use")
    parser.add_argument("--output", help="Output file path (default: linked post in posts/)")

    args = parser.parse_args()

    project_dir = Path(args.project_dir).resolve()

    if args.output:
        output_path = Path(args.output)
    else:
        output_path = find_post_path(project_dir)

    print(f"Project: {project_dir.name}")
    print(f"Output:  {output_path}")
    print("\nGathering source materials...")
    sources = gather_sources(project_dir)

    if (
        not sources["transcript"]
        and not sources["image_paths"]
        and not sources["pdf_paths"]
        and not sources["text_files"]
    ):
        print("Error: No source materials found.")
        sys.exit(1)

    blog_content = generate_blog(sources, args.model)

    # If the post file already exists, preserve its frontmatter draft status
    if output_path.exists():
        existing = output_path.read_text()
        # If generated content has frontmatter, ensure draft: true is set
        if blog_content.startswith("---"):
            if "draft:" not in blog_content:
                blog_content = blog_content.replace("---\n", "---\ndraft: true\n", 1)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(blog_content)

    print(f"\n✓ Blog post saved to {output_path}")
    print(f"  Word count: ~{len(blog_content.split())}")
    print(f"  Status: draft (run /publish to go live)")


if __name__ == "__main__":
    main()
