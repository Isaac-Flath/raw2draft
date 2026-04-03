"""Phase 1: Detect content mentions in transcript for overlay generation.

Scans the transcript for references to blog posts, talks, tools, people,
and key terms. Uses word-level timestamps to map each mention to source time.

Input: <stem>_analysis.json + <stem>_edl.json
Output: <stem>_mentions.json
"""

import json
import os
import re
import sys
from pathlib import Path


# ── Mention type patterns ────────────────────────────────────────────────────

# Phrases that indicate a blog post reference
BLOG_PATTERNS = [
    r"(?:i |we |I )?wrote (?:a |an )?(?:blog )?post (?:about|on|called|titled)",
    r"(?:i |we |I )?(?:published|released) (?:a |an )?(?:blog )?(?:post|article)",
    r"(?:my |our )?blog post (?:about|on|called|titled)",
    r"(?:there'?s|there is) (?:a |an )?(?:blog )?post (?:about|on)",
    r"(?:check out|read|see) (?:my |our |the )?(?:blog )?post",
    r"(?:in |on )?(?:my |our |the )?blog",
]

# Phrases that indicate a talk/presentation reference
TALK_PATTERNS = [
    r"(?:i |we )?(?:gave|did|presented) (?:a |an )?(?:talk|presentation|keynote|session)",
    r"(?:my |our )?(?:talk|presentation|keynote) (?:at|about|on|called|titled|from)",
    r"(?:there'?s|there is) (?:a |an )?(?:talk|presentation) (?:about|on|from)",
    r"(?:check out|watch|see) (?:my |our |the )?(?:talk|presentation)",
    r"(?:at |from )?(?:a |the )?conference",
]

# Phrases that indicate a tool/library/product reference
TOOL_PATTERNS = [
    r"(?:using|use|used|try|check out|install|import) (\w+(?:\.\w+)?(?:[-/]\w+)?)",
    r"(?:a |the )?(?:tool|library|framework|package|sdk|api) called (\w+(?:[-./]\w+)?)",
    r"(?:built (?:with|on|using)|powered by) (\w+(?:[-./]\w+)?)",
]

# URL patterns (spoken or in transcript)
URL_PATTERN = r"(?:https?://)?(?:www\.)?([a-zA-Z0-9][-a-zA-Z0-9]*(?:\.[a-zA-Z]{2,})+)(?:/[^\s,.)]*)*"

# Key term indicators
KEY_TERM_PATTERNS = [
    r"(?:this is (?:called|known as|what we call)) [\"']?(\w[\w\s]{1,40})[\"']?",
    r"(?:the concept of|the idea of|the term) [\"']?(\w[\w\s]{1,40})[\"']?",
    r"(?:what (?:i |we )?(?:call|mean by|refer to as)) [\"']?(\w[\w\s]{1,40})[\"']?",
]

# Person reference patterns
PERSON_PATTERNS = [
    r"(\w+ \w+) (?:wrote|created|built|invented|designed|proposed|introduced)",
    r"(?:by|from|according to) (\w+ \w+)",
    r"(\w+ \w+)(?:'s| 's) (?:work|paper|book|talk|blog|library|framework|tool|project)",
]


# ── Mention detection ────────────────────────────────────────────────────────

def _find_word_window(words, char_start, char_end, text):
    """Map character offsets in the full transcript text to word indices and timestamps."""
    # Build character offset map for each word
    pos = 0
    word_char_starts = []
    for w in words:
        # Find this word in text starting from pos
        idx = text.find(w["word"], pos)
        if idx == -1:
            idx = pos
        word_char_starts.append(idx)
        pos = idx + len(w["word"])

    # Find first word that overlaps char_start
    first_word = 0
    for i, wcs in enumerate(word_char_starts):
        if wcs + len(words[i]["word"]) > char_start:
            first_word = i
            break

    # Find last word that overlaps char_end
    last_word = len(words) - 1
    for i, wcs in enumerate(word_char_starts):
        if wcs >= char_end:
            last_word = max(0, i - 1)
            break

    return first_word, last_word


def _context_around(words, first_idx, last_idx, context_words=5):
    """Get text context around a mention."""
    start = max(0, first_idx - context_words)
    end = min(len(words), last_idx + context_words + 1)
    return " ".join(w["word"] for w in words[start:end])


def detect_mentions(analysis, edl):
    """Detect content mentions in the transcript.

    Returns a list of mention dicts with type, text, timing, and context.
    """
    words = analysis["transcript"]["words"]
    text = analysis["transcript"]["text"]
    source_file = analysis["source_file"]

    if not words or not text:
        return []

    # Build set of kept time ranges from EDL for filtering
    kept_ranges = []
    for seg in edl.get("segments", []):
        if seg.get("action") == "keep":
            kept_ranges.append((seg["start"], seg["end"]))

    mentions = []
    mention_id = 0

    def _add_mention(mention_type, label, match_start, match_end, url=None, extra_meta=None):
        nonlocal mention_id
        first_idx, last_idx = _find_word_window(words, match_start, match_end, text)

        source_start = words[first_idx]["start"]
        source_end = words[last_idx]["end"]

        # Check if this mention falls within a kept segment
        in_kept = any(
            ks <= source_start <= ke or ks <= source_end <= ke
            for ks, ke in kept_ranges
        )

        if not in_kept:
            return  # Skip mentions in cut segments

        mention_id += 1
        mention = {
            "id": f"mention_{mention_id:03d}",
            "type": mention_type,
            "label": label.strip(),
            "matched_text": text[match_start:match_end].strip(),
            "context": _context_around(words, first_idx, last_idx),
            "timing": {
                "source_start": round(source_start, 3),
                "source_end": round(source_end, 3),
            },
        }
        if url:
            mention["url"] = url
        if extra_meta:
            mention["metadata"] = extra_meta

        mentions.append(mention)

    # Detect blog post mentions
    for pattern in BLOG_PATTERNS:
        for m in re.finditer(pattern, text, re.IGNORECASE):
            # Try to extract the topic from text after the match
            after = text[m.end():m.end() + 100].strip()
            topic = after.split(".")[0].split(",")[0].strip()[:80]
            label = topic if topic else m.group(0)
            _add_mention("blog-card", label, m.start(), m.end())

    # Detect talk mentions
    for pattern in TALK_PATTERNS:
        for m in re.finditer(pattern, text, re.IGNORECASE):
            after = text[m.end():m.end() + 100].strip()
            topic = after.split(".")[0].split(",")[0].strip()[:80]
            label = topic if topic else m.group(0)
            _add_mention("talk-thumbnail", label, m.start(), m.end())

    # Detect URL mentions
    for m in re.finditer(URL_PATTERN, text):
        url = m.group(0)
        if not url.startswith("http"):
            url = "https://" + url
        domain = m.group(1)
        _add_mention("url-callout", domain, m.start(), m.end(), url=url)

    # Detect key term definitions
    for pattern in KEY_TERM_PATTERNS:
        for m in re.finditer(pattern, text, re.IGNORECASE):
            term = m.group(1).strip() if m.lastindex else m.group(0)
            _add_mention("key-term", term, m.start(), m.end())

    # Detect tool/library mentions (only well-known or explicitly named)
    for pattern in TOOL_PATTERNS:
        for m in re.finditer(pattern, text, re.IGNORECASE):
            tool_name = m.group(1) if m.lastindex else m.group(0)
            # Filter out very common/generic words
            if tool_name.lower() in {"it", "this", "that", "them", "something", "the", "a", "an"}:
                continue
            if len(tool_name) < 2:
                continue
            _add_mention("tool", tool_name, m.start(), m.end())

    # Deduplicate: if same label appears multiple times, keep the first occurrence
    seen_labels = set()
    deduped = []
    for mention in mentions:
        key = (mention["type"], mention["label"].lower())
        if key not in seen_labels:
            seen_labels.add(key)
            deduped.append(mention)

    # Sort by source_start time
    deduped.sort(key=lambda m: m["timing"]["source_start"])

    return deduped


# ── CLI ──────────────────────────────────────────────────────────────────────

def _find_project_root(start_path):
    """Walk up from start_path to find the project root."""
    current = os.path.dirname(start_path) if os.path.isfile(start_path) else start_path
    while current != os.path.dirname(current):
        if os.path.isdir(os.path.join(current, ".claude")) or os.path.isdir(os.path.join(current, ".git")):
            return current
        current = os.path.dirname(current)
    return os.path.dirname(start_path) if os.path.isfile(start_path) else start_path


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: uv run detect_mentions.py <analysis_json> <edl_json> [--output-dir <dir>]")
        sys.exit(1)

    analysis_path = sys.argv[1]
    edl_path = sys.argv[2]
    output_dir = None

    args = sys.argv[3:]
    i = 0
    while i < len(args):
        if args[i] == "--output-dir" and i + 1 < len(args):
            output_dir = args[i + 1]
            i += 2
        else:
            i += 1

    with open(analysis_path) as f:
        analysis = json.load(f)
    with open(edl_path) as f:
        edl = json.load(f)

    stem = Path(analysis["source_file"]).stem

    if output_dir is None:
        output_dir = os.path.dirname(os.path.abspath(analysis_path))
    os.makedirs(output_dir, exist_ok=True)

    print(f"Detecting mentions in: {stem}")
    mentions = detect_mentions(analysis, edl)
    print(f"  Found {len(mentions)} mentions:")

    for m in mentions:
        t = m["timing"]
        print(f"  [{t['source_start']:.1f}s] {m['type']}: {m['label']}")

    output = {
        "source_file": analysis["source_file"],
        "stem": stem,
        "mentions": mentions,
    }

    output_path = os.path.join(output_dir, f"{stem}_mentions.json")
    with open(output_path, "w") as f:
        json.dump(output, f, indent=2)
    print(f"\nMentions saved to {output_path}")
    print("Review these mentions and confirm which ones to overlay before proceeding.")
