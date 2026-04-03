#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "google-genai",
#     "pyyaml",
# ]
# ///
"""
Image generation using Gemini.

Usage:
    uv run generate_image.py "prompt" [output_path] [--model MODEL]

Requires:
    - GEMINI_API_KEY environment variable (or set in ~/.content/config.yaml)

Uses gemini-3-pro-image-preview by default.
"""

import argparse
import os
import sys
from pathlib import Path

import yaml
from google import genai
from google.genai import types


def load_global_config() -> dict:
    """Load global configuration from ~/.content/config.yaml if it exists."""
    global_config_path = Path.home() / ".content" / "config.yaml"
    if global_config_path.exists():
        with open(global_config_path) as f:
            return yaml.safe_load(f) or {}
    return {}


def get_gemini_client(global_config: dict | None = None) -> genai.Client:
    """Get Gemini client, preferring Vertex AI if available."""
    global_config = global_config or {}

    # Check for Vertex AI setup (like the main app)
    vertex_key = os.environ.get("VERTEX_AI_API_KEY") or os.environ.get("GOOGLE_API_KEY")
    if vertex_key and os.environ.get("GOOGLE_GENAI_USE_VERTEXAI", "").lower() == "true":
        os.environ["GOOGLE_API_KEY"] = vertex_key
        return genai.Client(vertexai=True, api_key=vertex_key)

    # Try environment variable first
    api_key = os.environ.get("GEMINI_API_KEY")

    # Fall back to global config
    if not api_key:
        api_keys = global_config.get("api_keys", {})
        api_key = api_keys.get("gemini")

    if not api_key:
        print("Error: GEMINI_API_KEY not set")
        print("  Set environment variable: export GEMINI_API_KEY=...")
        print("  Or add to ~/.content/config.yaml under api_keys.gemini")
        sys.exit(1)

    return genai.Client(api_key=api_key)


def generate_image(
    prompt: str,
    output_path: Path,
    model: str | None = None,
    global_config: dict | None = None,
) -> Path:
    """Generate an image using Gemini.

    Args:
        prompt: Text description of the image to generate
        output_path: Where to save the generated image
        model: Gemini model to use (default: gemini-3-pro-image-preview)
        global_config: Global configuration dict

    Returns:
        Path to the saved image
    """
    global_config = global_config or {}

    # Default model
    if not model:
        model = "gemini-3-pro-image-preview"

    client = get_gemini_client(global_config)

    print(f"Generating image with {model}...")
    print(f"Prompt: {prompt[:100]}{'...' if len(prompt) > 100 else ''}")

    response = client.models.generate_content(
        model=model,
        contents=prompt,
        config=types.GenerateContentConfig(
            response_modalities=["image", "text"],
        ),
    )

    # Extract image from response
    image_data = None
    mime_type = None

    for part in response.candidates[0].content.parts:
        if hasattr(part, "inline_data") and part.inline_data is not None:
            image_data = part.inline_data.data
            mime_type = part.inline_data.mime_type
            break

    if not image_data:
        print("Error: No image was generated")
        print("Response text:", response.text if hasattr(response, "text") else "None")
        sys.exit(1)

    # Determine file extension based on mime type
    ext = ".png"
    if mime_type:
        if "jpeg" in mime_type or "jpg" in mime_type:
            ext = ".jpg"
        elif "webp" in mime_type:
            ext = ".webp"

    # Add extension if not present
    if not output_path.suffix:
        output_path = output_path.with_suffix(ext)

    # Save image
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_bytes(image_data)

    # Print token usage if available
    if hasattr(response, "usage_metadata") and response.usage_metadata:
        usage = response.usage_metadata
        print(f"Tokens - input: {usage.prompt_token_count}, output: {usage.candidates_token_count}")

    print(f"✓ Image saved to {output_path}")
    return output_path


def slugify_prompt(prompt: str) -> str:
    """Create a filename from prompt."""
    import re
    slug = prompt.lower()[:50]
    slug = re.sub(r'[^\w\s-]', '', slug)
    slug = re.sub(r'[\s_]+', '-', slug)
    slug = re.sub(r'-+', '-', slug)
    return slug.strip('-') or "image"





def main():
    parser = argparse.ArgumentParser(
        description="Generate AI images using Gemini"
    )
    parser.add_argument(
        "prompt",
        help="Text description of the image to generate",
    )
    parser.add_argument(
        "output",
        nargs="?",
        default=None,
        help="Output file path",
    )
    parser.add_argument(
        "--project",
        default=None,
        help="Project directory (saves to {project}/images/)",
    )
    parser.add_argument(
        "--model",
        default=None,
        help="Gemini model to use (default: gemini-3-pro-image-preview)",
    )

    args = parser.parse_args()

    # Load global config
    global_config = load_global_config()

    # Determine output path
    if args.output:
        output_path = Path(args.output)
    elif args.project:
        project_dir = Path(args.project)
        images_dir = project_dir / "images"
        images_dir.mkdir(parents=True, exist_ok=True)
        filename = slugify_prompt(args.prompt) + ".png"
        output_path = images_dir / filename
    else:
        print("Error: Must specify output path or --project")
        print("\nUsage:")
        print('  generate_image.py "prompt" output.png')
        print('  generate_image.py "prompt" --project projects/2026_01_21_my-project')
        sys.exit(1)

    generate_image(args.prompt, output_path, args.model, global_config)


if __name__ == "__main__":
    main()
