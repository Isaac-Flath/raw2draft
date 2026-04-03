"""Generate YouTube chapter markers from transcript + EDL.

Analyzes the transcript to identify topic boundaries, then maps timestamps
through the EDL to the edited timeline.

Input: <stem>_analysis.json + <stem>_edl.json
Output: <stem>_chapters.txt (YouTube format) + <stem>_chapters.json
"""

import json
import math
import os
import re
import sys
from collections import Counter
from pathlib import Path


# ── Transition detection patterns ────────────────────────────────────────────

TRANSITION_PHRASES = [
    r"\b(?:now |so |okay |alright )?let'?s (?:talk about|look at|move on|dive into|get into|start with|switch to)",
    r"\b(?:moving on|next up|next thing|the next|another thing|on to)",
    r"\b(?:first|second|third|fourth|fifth|finally|lastly|to start|to begin)",
    r"\bso (?:the |that |this )?(?:first|second|next|last|final)",
    r"\b(?:now|okay|alright|so),? (?:the |this |that )?(?:big|main|key|important|interesting) (?:thing|point|question|idea)",
    r"\b(?:before we|before i) (?:go|move|wrap|finish)",
    r"\b(?:to (?:wrap|sum) (?:up|things up)|in (?:summary|conclusion))",
]

# Words that suggest topic/subject changes when appearing in clusters
TOPIC_SIGNAL_WORDS = {
    "example", "demo", "demonstration", "setup", "install", "installation",
    "configuration", "config", "architecture", "design", "implementation",
    "overview", "introduction", "intro", "summary", "conclusion",
    "problem", "solution", "challenge", "approach", "comparison",
    "benefit", "advantage", "disadvantage", "limitation", "feature",
    "step", "part", "section", "chapter", "phase",
}

# Minimum chapter duration (seconds) -- avoid very short chapters
MIN_CHAPTER_DURATION = 30.0

# Target chapter count range
MIN_CHAPTERS = 3
MAX_CHAPTERS = 15


# ── Timeline mapping ─────────────────────────────────────────────────────────

def build_timeline_map(edl_segments):
    """Build source-to-timeline mapping from EDL segments."""
    kept = sorted(
        [s for s in edl_segments if s.get("action") == "keep"],
        key=lambda s: s["start"],
    )
    timeline_map = []
    timeline_pos = 0.0
    for seg in kept:
        timeline_map.append((seg["start"], seg["end"], timeline_pos))
        timeline_pos += seg["end"] - seg["start"]
    return timeline_map


def source_to_timeline(source_time, timeline_map):
    """Map source timestamp to timeline position."""
    for src_start, src_end, tl_start in timeline_map:
        if src_start <= source_time <= src_end:
            return tl_start + (source_time - src_start)
    # Find nearest
    best_tl = 0.0
    best_dist = float("inf")
    for src_start, src_end, tl_start in timeline_map:
        for src_t, tl_t in [(src_start, tl_start), (src_end, tl_start + (src_end - src_start))]:
            dist = abs(source_time - src_t)
            if dist < best_dist:
                best_dist = dist
                best_tl = tl_t
    return best_tl


# ── Chapter detection ────────────────────────────────────────────────────────

def _get_word_windows(words, window_seconds=30.0):
    """Split words into time windows for topic analysis."""
    if not words:
        return []
    windows = []
    current = []
    window_start = words[0]["start"]

    for w in words:
        if w["start"] - window_start >= window_seconds and current:
            windows.append({
                "start": window_start,
                "end": current[-1]["end"],
                "words": current,
                "text": " ".join(wd["word"] for wd in current),
            })
            current = [w]
            window_start = w["start"]
        else:
            current.append(w)

    if current:
        windows.append({
            "start": window_start,
            "end": current[-1]["end"],
            "words": current,
            "text": " ".join(wd["word"] for wd in current),
        })

    return windows


def _detect_transition_points(words, text):
    """Find timestamps where transition phrases occur."""
    transitions = []
    for pattern in TRANSITION_PHRASES:
        for m in re.finditer(pattern, text, re.IGNORECASE):
            char_pos = m.start()
            # Map to word timestamp
            pos = 0
            for w in words:
                idx = text.find(w["word"], pos)
                if idx >= char_pos:
                    transitions.append({
                        "time": w["start"],
                        "phrase": m.group(0),
                        "score": 1.0,
                    })
                    break
                pos = idx + len(w["word"])
    return transitions


def _detect_pause_boundaries(words, silences, min_pause=2.0):
    """Find long pauses that may indicate topic changes."""
    boundaries = []
    for i in range(1, len(words)):
        gap = words[i]["start"] - words[i - 1]["end"]
        if gap >= min_pause:
            boundaries.append({
                "time": words[i]["start"],
                "phrase": f"({gap:.1f}s pause)",
                "score": min(gap / 3.0, 1.0),
            })

    for silence in silences:
        if silence.get("duration", 0) >= min_pause:
            boundaries.append({
                "time": silence.get("end", silence["start"]),
                "phrase": f"({silence.get('duration', 0):.1f}s silence)",
                "score": min(silence.get("duration", 0) / 4.0, 1.0),
            })

    return boundaries


def _detect_vocabulary_shifts(windows):
    """Detect points where vocabulary changes significantly."""
    if len(windows) < 2:
        return []

    shifts = []
    for i in range(1, len(windows)):
        prev_words = set(re.sub(r"[^\w\s]", "", windows[i - 1]["text"].lower()).split())
        curr_words = set(re.sub(r"[^\w\s]", "", windows[i]["text"].lower()).split())

        # Jaccard distance
        intersection = len(prev_words & curr_words)
        union = len(prev_words | curr_words)
        similarity = intersection / union if union > 0 else 1.0
        novelty = 1.0 - similarity

        # Check for topic signal words
        new_signals = curr_words & TOPIC_SIGNAL_WORDS - prev_words
        signal_bonus = 0.2 * len(new_signals)

        score = min(novelty + signal_bonus, 1.0)
        if score > 0.4:
            shifts.append({
                "time": windows[i]["start"],
                "phrase": f"(topic shift, novelty={novelty:.2f})",
                "score": score,
            })

    return shifts


def _generate_chapter_title(words, max_words=6):
    """Generate a chapter title from the first few substantive words after a boundary."""
    stop = {"um", "uh", "like", "so", "okay", "alright", "well", "and", "but",
            "the", "a", "an", "i", "we", "you", "it", "is", "are", "was", "to",
            "of", "in", "for", "this", "that", "let's", "let", "now", "right"}

    substantive = []
    for w in words[:20]:
        clean = re.sub(r"[^\w]", "", w["word"].lower())
        if clean and clean not in stop:
            substantive.append(w["word"].rstrip(".,!?;:"))
            if len(substantive) >= max_words:
                break

    if substantive:
        title = " ".join(substantive)
        return title[0].upper() + title[1:]
    return "Untitled Section"


def generate_chapters(analysis, edl, silences=None):
    """Generate chapter markers from analysis and EDL.

    Returns list of chapter dicts with timeline timestamps.
    """
    words = analysis["transcript"]["words"]
    text = analysis["transcript"]["text"]
    total_duration = analysis["metadata"]["duration"]

    if not words:
        return []

    silences = silences or analysis.get("silences", [])
    timeline_map = build_timeline_map(edl.get("segments", []))

    # Get the edited total duration
    edited_duration = sum(
        s["end"] - s["start"]
        for s in edl.get("segments", [])
        if s.get("action") == "keep"
    )

    # Collect all candidate boundaries
    candidates = []
    candidates.extend(_detect_transition_points(words, text))
    candidates.extend(_detect_pause_boundaries(words, silences))

    windows = _get_word_windows(words)
    candidates.extend(_detect_vocabulary_shifts(windows))

    # Deduplicate candidates within 5 seconds of each other (keep highest score)
    candidates.sort(key=lambda c: c["time"])
    deduped = []
    for cand in candidates:
        if deduped and cand["time"] - deduped[-1]["time"] < 5.0:
            if cand["score"] > deduped[-1]["score"]:
                deduped[-1] = cand
        else:
            deduped.append(cand)

    # Sort by score and take top candidates
    deduped.sort(key=lambda c: c["score"], reverse=True)
    top_candidates = deduped[:MAX_CHAPTERS * 2]

    # Sort back by time
    top_candidates.sort(key=lambda c: c["time"])

    # Build chapters, enforcing minimum duration
    chapters = [{
        "source_time": 0.0,
        "title": "Introduction",
    }]

    for cand in top_candidates:
        # Check minimum duration from last chapter
        if cand["time"] - chapters[-1]["source_time"] < MIN_CHAPTER_DURATION:
            continue

        # Find words right after this boundary for title generation
        after_words = [w for w in words if w["start"] >= cand["time"]][:20]
        title = _generate_chapter_title(after_words)

        chapters.append({
            "source_time": cand["time"],
            "title": title,
            "detection_info": cand["phrase"],
        })

    # Ensure we don't have too many chapters
    while len(chapters) > MAX_CHAPTERS:
        # Remove the chapter with the shortest duration (except first)
        min_dur = float("inf")
        min_idx = 1
        for i in range(1, len(chapters)):
            next_time = chapters[i + 1]["source_time"] if i + 1 < len(chapters) else total_duration
            dur = next_time - chapters[i]["source_time"]
            if dur < min_dur:
                min_dur = dur
                min_idx = i
        chapters.pop(min_idx)

    # Map to timeline timestamps
    for ch in chapters:
        ch["timeline_time"] = source_to_timeline(ch["source_time"], timeline_map)

    return chapters


def format_youtube_chapters(chapters):
    """Format chapters as YouTube description text."""
    lines = []
    for ch in chapters:
        t = ch["timeline_time"]
        minutes = int(t // 60)
        seconds = int(t % 60)
        lines.append(f"{minutes}:{seconds:02d} {ch['title']}")
    return "\n".join(lines)


# ── CLI ──────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: uv run generate_chapters.py <analysis_json> <edl_json> [--output-dir <dir>]")
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

    print(f"Generating chapters for: {stem}")
    chapters = generate_chapters(analysis, edl)
    print(f"  Found {len(chapters)} chapters:")

    youtube_text = format_youtube_chapters(chapters)
    print(f"\n{youtube_text}\n")

    # Save YouTube format
    txt_path = os.path.join(output_dir, f"{stem}_chapters.txt")
    with open(txt_path, "w") as f:
        f.write(youtube_text)
    print(f"YouTube chapters saved to {txt_path}")

    # Save structured JSON
    json_path = os.path.join(output_dir, f"{stem}_chapters.json")
    with open(json_path, "w") as f:
        json.dump({
            "source_file": analysis["source_file"],
            "stem": stem,
            "chapters": chapters,
        }, f, indent=2)
    print(f"Chapter data saved to {json_path}")
    print("\nReview these chapters and adjust titles/boundaries as needed.")
