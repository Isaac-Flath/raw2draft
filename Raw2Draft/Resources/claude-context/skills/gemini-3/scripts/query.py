#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "google-generativeai",
#     "pyyaml",
# ]
# ///
"""
General-purpose Gemini query tool.

Usage:
    uv run query.py "prompt" [--model MODEL] [--image PATH] [--file PATH] [--context PATH]

Examples:
    # Simple query
    uv run query.py "Explain quantum computing"

    # With context files (prepended to prompt)
    uv run query.py "Generate a summary" --context style.md --context blog.md

    # With image/PDF files (sent as attachments)
    uv run query.py "Describe this" --file image.png

Requires:
    - GEMINI_API_KEY environment variable (or set in ~/.content/config.yaml)
"""

import argparse
import base64
import mimetypes
import os
import sys
from pathlib import Path

import yaml
import google.generativeai as genai


def load_global_config() -> dict:
    """Load global configuration from ~/.content/config.yaml if it exists."""
    global_config_path = Path.home() / ".content" / "config.yaml"
    if global_config_path.exists():
        with open(global_config_path) as f:
            return yaml.safe_load(f) or {}
    return {}


def get_api_key(global_config: dict | None = None) -> str | None:
    """Get Gemini API key from environment or config."""
    global_config = global_config or {}

    # Try environment variable first
    api_key = os.environ.get("GEMINI_API_KEY")

    # Fall back to global config
    if not api_key:
        api_keys = global_config.get("api_keys", {})
        api_key = api_keys.get("gemini")

    return api_key


def load_file(path: Path) -> dict | None:
    """Load a file (image or document) for Gemini API."""
    if not path.exists():
        print(f"Error: File not found: {path}", file=sys.stderr)
        return None

    mime_type, _ = mimetypes.guess_type(str(path))
    if not mime_type:
        # Default to application/octet-stream
        mime_type = "application/octet-stream"

    with open(path, "rb") as f:
        data = base64.b64encode(f.read()).decode("utf-8")

    return {"mime_type": mime_type, "data": data}


def load_context_files(paths: list[Path]) -> str:
    """Load text files and combine them into context string.

    Args:
        paths: List of text file paths to load

    Returns:
        Combined context string with file separators
    """
    context_parts = []

    for path in paths:
        if not path.exists():
            print(f"Warning: Context file not found: {path}", file=sys.stderr)
            continue

        try:
            content = path.read_text()
            context_parts.append(f"# Context from: {path.name}\n\n{content}")
            print(f"Loaded context: {path} ({len(content)} chars)", file=sys.stderr)
        except Exception as e:
            print(f"Warning: Could not read {path}: {e}", file=sys.stderr)

    if context_parts:
        return "\n\n---\n\n".join(context_parts) + "\n\n---\n\n"
    return ""


def query_gemini(
    prompt: str,
    model: str = "gemini-2.5-pro",
    files: list[Path] | None = None,
    context_files: list[Path] | None = None,
    global_config: dict | None = None,
) -> str:
    """Query Gemini with a prompt and optional files.

    Args:
        prompt: Text prompt
        model: Gemini model to use
        files: Optional list of file paths (images, PDFs, etc.)
        context_files: Optional list of text files to prepend as context
        global_config: Global configuration dict

    Returns:
        Response text from Gemini
    """
    global_config = global_config or {}

    api_key = get_api_key(global_config)
    if not api_key:
        print("Error: GEMINI_API_KEY not set", file=sys.stderr)
        print("  Set environment variable: export GEMINI_API_KEY=...", file=sys.stderr)
        print("  Or add to ~/.content/config.yaml under api_keys.gemini", file=sys.stderr)
        sys.exit(1)

    genai.configure(api_key=api_key)

    # Build the full prompt with context
    full_prompt = prompt
    if context_files:
        context = load_context_files(context_files)
        full_prompt = context + "# Task\n\n" + prompt

    # Build content parts
    content_parts = [full_prompt]

    if files:
        for file_path in files:
            file_data = load_file(file_path)
            if file_data:
                content_parts.append(file_data)
                print(f"Loaded: {file_path} ({file_data['mime_type']})", file=sys.stderr)

    # Query the model
    print(f"Querying {model}...", file=sys.stderr)
    print(f"Prompt: {prompt[:100]}{'...' if len(prompt) > 100 else ''}", file=sys.stderr)

    model_obj = genai.GenerativeModel(model)
    response = model_obj.generate_content(content_parts)

    # Print token usage if available
    if hasattr(response, "usage_metadata") and response.usage_metadata:
        usage = response.usage_metadata
        print(f"\nTokens - input: {usage.prompt_token_count}, output: {usage.candidates_token_count}", file=sys.stderr)

    return response.text


def main():
    parser = argparse.ArgumentParser(
        description="Query Gemini models for general-purpose tasks"
    )
    parser.add_argument(
        "prompt",
        help="Text prompt to send to Gemini",
    )
    parser.add_argument(
        "--model",
        default="gemini-2.5-pro",
        help="Gemini model to use (default: gemini-2.5-pro)",
    )
    parser.add_argument(
        "--image",
        action="append",
        dest="files",
        type=Path,
        help="Image file to include (can be used multiple times)",
    )
    parser.add_argument(
        "--file",
        action="append",
        dest="files",
        type=Path,
        help="File to include (PDF, image, etc., can be used multiple times)",
    )
    parser.add_argument(
        "--context",
        action="append",
        dest="context_files",
        type=Path,
        help="Text file to prepend as context (can be used multiple times)",
    )

    args = parser.parse_args()

    # Load global config
    global_config = load_global_config()

    # Query Gemini
    response_text = query_gemini(
        args.prompt,
        args.model,
        args.files,
        args.context_files,
        global_config,
    )

    # Print response to stdout
    print(response_text)


if __name__ == "__main__":
    main()
