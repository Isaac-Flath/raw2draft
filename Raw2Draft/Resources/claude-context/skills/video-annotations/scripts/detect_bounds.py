#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "google-generativeai",
#     "pyyaml",
# ]
# ///
"""Detect bounding boxes for text or objects in a video frame using Gemini vision.

Usage:
    uv run scripts/detect_bounds.py <frame.png> "the robot character"
    uv run scripts/detect_bounds.py <frame.png> "the words 'fully understand'"
    uv run scripts/detect_bounds.py <frame.png> --all "List all distinct visual elements"

Returns JSON bounding boxes: {"target": ..., "bounds": {"x": ..., "y": ..., "width": ..., "height": ...}}

This replaces both EasyOCR (for text) and rough Gemini coordinate guessing (for objects)
by using structured prompting that asks Gemini for precise bounding boxes.
"""

import base64
import json
import os
import sys
from pathlib import Path

import yaml


def get_api_key() -> str:
    key = os.environ.get("GEMINI_API_KEY")
    if not key:
        config_path = Path.home() / ".content" / "config.yaml"
        if config_path.exists():
            with open(config_path) as f:
                config = yaml.safe_load(f) or {}
            key = config.get("api_keys", {}).get("gemini")
    if not key:
        # Try .env in repo root
        env_path = Path(__file__).parent.parent.parent.parent / ".env"
        if env_path.exists():
            for line in env_path.read_text().splitlines():
                if line.startswith("GEMINI_API_KEY="):
                    key = line.split("=", 1)[1].strip()
    if not key:
        print("ERROR: GEMINI_API_KEY not found", file=sys.stderr)
        sys.exit(1)
    return key


def detect_bounds(frame_path: str, target: str) -> list[dict]:
    """Ask Gemini for precise bounding boxes of a target in an image."""
    import google.generativeai as genai

    api_key = get_api_key()
    genai.configure(api_key=api_key)

    with open(frame_path, "rb") as f:
        image_data = base64.b64encode(f.read()).decode("utf-8")

    prompt = f"""You are a precise visual annotation tool. The image is a 1920x1080 video frame.

Find this target: "{target}"

Return ONLY a JSON array of bounding boxes. Each bounding box must have:
- "target": what was found (brief description)
- "x": left edge in pixels from frame left (0-1920)
- "y": top edge in pixels from frame top (0-1080)
- "width": width in pixels
- "height": height in pixels
- "center_x": center x coordinate
- "center_y": center y coordinate
- "confidence": your confidence 0-1

Rules:
- Coordinates are pixels from top-left corner of the 1920x1080 frame
- The bounding box must TIGHTLY contain the target — no extra padding
- If the target is text, the box should wrap the text baseline to ascender
- If the target is an object/character, the box should contain the full object
- Return [] if the target is not found
- Return ONLY the JSON array, no markdown fences, no explanation

Example response:
[{{"target": "the word hello", "x": 400, "y": 200, "width": 120, "height": 30, "center_x": 460, "center_y": 215, "confidence": 0.95}}]"""

    model = genai.GenerativeModel("gemini-2.5-pro")
    response = model.generate_content([
        prompt,
        {"mime_type": "image/png", "data": image_data},
    ])

    text = response.text.strip()
    # Strip markdown fences if present
    if text.startswith("```"):
        text = text.split("\n", 1)[1]
        if text.endswith("```"):
            text = text.rsplit("```", 1)[0]
        text = text.strip()

    try:
        return json.loads(text)
    except json.JSONDecodeError:
        print(f"WARNING: Could not parse Gemini response as JSON:", file=sys.stderr)
        print(text, file=sys.stderr)
        return []


def detect_all(frame_path: str) -> list[dict]:
    """Ask Gemini to identify all major visual elements with bounding boxes."""
    import google.generativeai as genai

    api_key = get_api_key()
    genai.configure(api_key=api_key)

    with open(frame_path, "rb") as f:
        image_data = base64.b64encode(f.read()).decode("utf-8")

    prompt = """You are a precise visual annotation tool. The image is a 1920x1080 video frame.

Identify ALL distinct visual elements: text labels, UI components, characters, icons, buttons, images.

Return ONLY a JSON array of bounding boxes. Each must have:
- "target": description of the element
- "x": left edge pixels from frame left (0-1920)
- "y": top edge pixels from frame top (0-1080)
- "width": width in pixels
- "height": height in pixels
- "center_x": center x coordinate
- "center_y": center y coordinate

Rules:
- Coordinates are pixels from top-left of the 1920x1080 frame
- Bounding boxes should TIGHTLY contain each element
- Return ONLY the JSON array, no markdown fences, no explanation"""

    model = genai.GenerativeModel("gemini-2.5-pro")
    response = model.generate_content([
        prompt,
        {"mime_type": "image/png", "data": image_data},
    ])

    text = response.text.strip()
    if text.startswith("```"):
        text = text.split("\n", 1)[1]
        if text.endswith("```"):
            text = text.rsplit("```", 1)[0]
        text = text.strip()

    try:
        return json.loads(text)
    except json.JSONDecodeError:
        print(f"WARNING: Could not parse Gemini response as JSON:", file=sys.stderr)
        print(text, file=sys.stderr)
        return []


def main():
    if len(sys.argv) < 3:
        print("Usage:")
        print('  detect_bounds.py <frame.png> "target description"')
        print('  detect_bounds.py <frame.png> --all')
        sys.exit(1)

    frame_path = sys.argv[1]
    if not Path(frame_path).exists():
        print(f"ERROR: Frame not found: {frame_path}", file=sys.stderr)
        sys.exit(1)

    if sys.argv[2] == "--all":
        results = detect_all(frame_path)
    else:
        target = sys.argv[2]
        results = detect_bounds(frame_path, target)

    print(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()
