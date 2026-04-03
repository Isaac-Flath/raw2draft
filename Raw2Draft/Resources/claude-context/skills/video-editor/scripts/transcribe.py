#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.13"
# dependencies = [
#     "assemblyai>=0.54.1",
#     "python-dotenv>=1.2.2",
# ]
# ///
"""AssemblyAI transcription helper with verbatim disfluency preservation."""

import json
import os
import sys

import assemblyai as aai
from dotenv import load_dotenv


def transcribe_video(video_path: str, env_path: str | None = None) -> dict:
    """Transcribe a video file using AssemblyAI with disfluencies preserved.

    Returns dict with 'text', 'segments', 'words' keys.
    """
    if env_path:
        load_dotenv(env_path)
    else:
        load_dotenv()

    aai.settings.api_key = os.getenv("ASSEMBLYAI_API_KEY")

    config = aai.TranscriptionConfig(
        speech_models=["universal-3-pro", "universal-2"],
        disfluencies=True,
    )

    transcriber = aai.Transcriber()
    transcript = transcriber.transcribe(video_path, config=config)

    if transcript.status == aai.TranscriptStatus.error:
        raise RuntimeError(f"Transcription failed: {transcript.error}")

    # Convert to existing format (AssemblyAI timestamps are in ms → seconds)
    words = [
        {"word": w.text, "start": w.start / 1000, "end": w.end / 1000}
        for w in transcript.words
    ]

    return {"text": transcript.text, "words": words, "segments": None}


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: uv run transcribe.py <video_path> [--env-path <path>] [--output <path>]")
        sys.exit(1)

    video_path = sys.argv[1]
    env_path = None
    output_path = None

    args = sys.argv[2:]
    i = 0
    while i < len(args):
        if args[i] == "--env-path" and i + 1 < len(args):
            env_path = args[i + 1]
            i += 2
        elif args[i] == "--output" and i + 1 < len(args):
            output_path = args[i + 1]
            i += 2
        else:
            i += 1

    result = transcribe_video(video_path, env_path)

    if output_path:
        os.makedirs(os.path.dirname(output_path), exist_ok=True)
        with open(output_path, "w") as f:
            json.dump(result, f, indent=2)
        print(f"Transcript saved to {output_path}")
    else:
        print(json.dumps(result, indent=2))
