#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "openai",
#     "pyyaml",
# ]
# ///
"""
General-purpose OpenAI query tool.

Usage:
    uv run query.py "prompt" [--model MODEL] [--image PATH] [--system SYSTEM]

Requires:
    - OPENAI_API_KEY environment variable (or set in ~/.content/config.yaml)
"""

import argparse
import base64
import os
import sys
from pathlib import Path

import yaml
from openai import OpenAI


def load_global_config() -> dict:
    """Load global configuration from ~/.content/config.yaml if it exists."""
    global_config_path = Path.home() / ".content" / "config.yaml"
    if global_config_path.exists():
        with open(global_config_path) as f:
            return yaml.safe_load(f) or {}
    return {}


def get_api_key(global_config: dict | None = None) -> str | None:
    """Get OpenAI API key from environment or config."""
    global_config = global_config or {}

    # Try environment variable first
    api_key = os.environ.get("OPENAI_API_KEY")

    # Fall back to global config
    if not api_key:
        api_keys = global_config.get("api_keys", {})
        api_key = api_keys.get("openai")

    return api_key


def encode_image(image_path: Path) -> str:
    """Encode image to base64 for OpenAI API."""
    with open(image_path, "rb") as f:
        return base64.b64encode(f.read()).decode("utf-8")


def query_openai(
    prompt: str,
    model: str = "gpt-4o",
    system_message: str | None = None,
    images: list[Path] | None = None,
    global_config: dict | None = None,
) -> str:
    """Query OpenAI with a prompt and optional images.

    Args:
        prompt: Text prompt
        model: OpenAI model to use
        system_message: Optional system message
        images: Optional list of image paths (for vision models)
        global_config: Global configuration dict

    Returns:
        Response text from OpenAI
    """
    global_config = global_config or {}

    api_key = get_api_key(global_config)
    if not api_key:
        print("Error: OPENAI_API_KEY not set", file=sys.stderr)
        print("  Set environment variable: export OPENAI_API_KEY=...", file=sys.stderr)
        print("  Or add to ~/.content/config.yaml under api_keys.openai", file=sys.stderr)
        sys.exit(1)

    client = OpenAI(api_key=api_key)

    # Build messages
    messages = []

    if system_message:
        messages.append({"role": "system", "content": system_message})

    # Build user message with optional images
    user_content = []

    if images:
        # Vision mode - add images
        for image_path in images:
            if not image_path.exists():
                print(f"Error: Image not found: {image_path}", file=sys.stderr)
                sys.exit(1)

            base64_image = encode_image(image_path)
            user_content.append({
                "type": "image_url",
                "image_url": {
                    "url": f"data:image/jpeg;base64,{base64_image}"
                }
            })
            print(f"Loaded image: {image_path}", file=sys.stderr)

    # Add text prompt
    user_content.append({
        "type": "text",
        "text": prompt
    })

    messages.append({
        "role": "user",
        "content": user_content if images else prompt
    })

    # Query the model
    print(f"Querying {model}...", file=sys.stderr)
    print(f"Prompt: {prompt[:100]}{'...' if len(prompt) > 100 else ''}", file=sys.stderr)

    response = client.chat.completions.create(
        model=model,
        messages=messages,
    )

    # Print token usage
    if response.usage:
        print(f"\nTokens - input: {response.usage.prompt_tokens}, output: {response.usage.completion_tokens}", file=sys.stderr)

    return response.choices[0].message.content


def main():
    parser = argparse.ArgumentParser(
        description="Query OpenAI models for general-purpose tasks"
    )
    parser.add_argument(
        "prompt",
        help="Text prompt to send to OpenAI",
    )
    parser.add_argument(
        "--model",
        default="gpt-4o",
        help="OpenAI model to use (default: gpt-4o)",
    )
    parser.add_argument(
        "--system",
        help="System message to set context/behavior",
    )
    parser.add_argument(
        "--image",
        action="append",
        dest="images",
        type=Path,
        help="Image file to include (can be used multiple times, vision models only)",
    )

    args = parser.parse_args()

    # Load global config
    global_config = load_global_config()

    # Query OpenAI
    response_text = query_openai(
        args.prompt,
        args.model,
        args.system,
        args.images,
        global_config,
    )

    # Print response to stdout
    print(response_text)


if __name__ == "__main__":
    main()
