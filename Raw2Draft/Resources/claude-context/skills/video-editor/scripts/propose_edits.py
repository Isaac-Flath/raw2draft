#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.13"
# dependencies = []
# ///
"""Phase 2: Propose edits mechanically — take detection, filler removal, silence normalization.

Input: <stem>_analysis.json (from Phase 1)
Output: <stem>_edl.json (draft EDL) + <stem>_review.md (human-readable review)

Five-pass pipeline:
1. Utterance segmentation (split words by gaps)
2. Take detection (repeated starts → keep last complete version)
3. Filler removal (surgical sub-clip splits around fillers)
4. Incomplete sentence trimming (trailing fillers/conjunctions)
5. Silence normalization (consistent inter-segment gaps)
"""

import json
import os
import re
import sys
from copy import deepcopy
from difflib import SequenceMatcher
from pathlib import Path

# ── Configurable thresholds ──────────────────────────────────────────────────

GAP_THRESHOLD = 0.6         # seconds gap to split utterances
SIM_THRESHOLD = 0.5         # text similarity ratio to flag as repeated take
PREFIX_MATCH_WORDS = 3      # matching first N substantive words = repeated take
FILLER_WORDS = {"um", "uh", "like", "you know", "so", "and so", "and then"}
FILLER_BIGRAMS = {"you know", "and so", "and then"}
MIN_SEGMENT_DURATION = 0.25 # don't create sub-clips shorter than this
TARGET_GAP = 0.8            # reduce silences to this
MIN_GAP = 0.3               # minimum silence between segments
PRE_PADDING = 0.12          # padding before first word in segment
POST_PADDING = 0.25         # padding after last word in segment
PRE_ROLL = 1.0              # pre-roll before first word of entire video
POST_ROLL = 1.0             # post-roll after last word of entire video

# Words to skip when comparing utterance starts (not substantive)
STOP_WORDS = {"um", "uh", "like", "so", "and", "but", "the", "a", "an", "i",
              "you", "we", "it", "is", "was", "that", "this", "to", "of", "in",
              "okay", "ok", "alright", "yeah", "yes", "no", "well", "right"}

# Trailing words that indicate an incomplete sentence
TRAILING_INCOMPLETE = {"um", "uh", "and", "so", "but", "or", "like", "because",
                       "the", "a", "an", "to", "of", "in", "for", "with", "that"}


# ── Data structures ──────────────────────────────────────────────────────────

def make_segment(words, action="keep", reason="", flags=None):
    """Create a segment dict from a list of word dicts."""
    if not words:
        return None
    text = " ".join(w["word"] for w in words)
    return {
        "start": words[0]["start"],
        "end": words[-1]["end"],
        "action": action,
        "words": words,
        "text": text,
        "reason": reason,
        "flags": flags or [],
    }


# ── Pass 1: Utterance segmentation ──────────────────────────────────────────

def segment_utterances(words, gap_threshold=GAP_THRESHOLD):
    """Group words into utterances by gaps between them."""
    if not words:
        return []

    segments = []
    current_words = [words[0]]

    for i in range(1, len(words)):
        gap = words[i]["start"] - words[i - 1]["end"]
        if gap > gap_threshold:
            seg = make_segment(current_words)
            if seg:
                segments.append(seg)
            current_words = [words[i]]
        else:
            current_words.append(words[i])

    # Last segment
    seg = make_segment(current_words)
    if seg:
        segments.append(seg)

    return segments


# ── Pass 2: Take detection ───────────────────────────────────────────────────

def _substantive_words(text):
    """Extract substantive (non-stop) words from text, lowercased and stripped of punctuation."""
    words = re.sub(r"[^\w\s]", "", text.lower()).split()
    return [w for w in words if w not in STOP_WORDS]


def _all_words_lower(text):
    """All words lowercased and stripped of punctuation."""
    return re.sub(r"[^\w\s]", "", text.lower()).split()


def _prefix_matches(text_a, text_b, n=PREFIX_MATCH_WORDS):
    """Check if two texts share the same first N substantive words."""
    words_a = _substantive_words(text_a)
    words_b = _substantive_words(text_b)
    if len(words_a) < n or len(words_b) < n:
        return False
    return words_a[:n] == words_b[:n]


def _text_similarity(text_a, text_b):
    """Compute similarity ratio between two texts (0-1)."""
    return SequenceMatcher(None, text_a.lower(), text_b.lower()).ratio()


def _split_within_utterance_repeats(seg):
    """Detect and split within-utterance repeated starts.

    Handles cases like: "So you've probably heard so you've probably heard of
    claude so you've probably heard of claude code and how..."
    where the speaker restarts mid-utterance without a long pause.

    Returns a list of segments (possibly just the original if no repeats found).
    """
    words = seg["words"]
    if len(words) < 6:  # Too short for within-utterance repeats
        return [seg]

    # Build list of lowercase stripped words for matching
    clean = [re.sub(r"[^\w]", "", w["word"].lower()) for w in words]

    # Look for repeated prefixes: sliding window approach
    # Find positions where a sequence of 3+ words matches an earlier position
    repeat_starts = []  # (start_idx, end_idx) of repeated prefixes to cut

    i = 0
    while i < len(words) - 3:
        # Look ahead for the same 3-word sequence starting later
        best_j = None
        for j in range(i + 2, min(i + 30, len(words) - 2)):
            # Check if words at j match words at i (3+ word prefix)
            match_len = 0
            for k in range(min(8, len(words) - j, len(words) - i)):
                if clean[i + k] == clean[j + k] and clean[i + k]:
                    match_len += 1
                else:
                    break
            if match_len >= 3:
                best_j = j
                # Don't break — keep looking for later repeats (keep last)
        if best_j is not None:
            # Everything from i to best_j-1 is an earlier take to cut
            repeat_starts.append((i, best_j))
            i = best_j  # Jump to the last repeat
        else:
            i += 1

    if not repeat_starts:
        return [seg]

    # Build segments: cut the repeated prefixes, keep the rest
    result = []
    kept_ranges = []
    cut_ranges = []

    # Merge overlapping repeat ranges
    merged = [repeat_starts[0]]
    for start, end in repeat_starts[1:]:
        if start <= merged[-1][1]:
            merged[-1] = (merged[-1][0], max(merged[-1][1], end))
        else:
            merged.append((start, end))

    # Build kept/cut ranges
    pos = 0
    for cut_start, cut_end in merged:
        if pos < cut_start:
            kept_ranges.append((pos, cut_start))
        cut_ranges.append((cut_start, cut_end))
        pos = cut_end
    if pos < len(words):
        kept_ranges.append((pos, len(words)))

    for start, end in kept_ranges:
        sub_words = words[start:end]
        if sub_words:
            sub = make_segment(sub_words, action="keep",
                               reason=seg.get("reason", ""),
                               flags=list(seg.get("flags", [])))
            if sub:
                result.append(sub)

    for start, end in cut_ranges:
        sub_words = words[start:end]
        if sub_words:
            sub = make_segment(sub_words, action="cut",
                               reason="within-utterance repeated take")
            if sub:
                result.append(sub)

    result.sort(key=lambda s: s["start"])
    return result


def detect_repeated_takes(segments, lookahead=20, sim_threshold=SIM_THRESHOLD):
    """Detect repeated takes and keep the last complete version.

    For each segment, look ahead up to `lookahead` segments for similar starts.
    Group as repeated takes. Keep the last complete version.
    Also detects within-utterance repetitions.
    """
    # First pass: split within-utterance repeats
    expanded = []
    for seg in segments:
        if seg["action"] == "keep":
            expanded.extend(_split_within_utterance_repeats(seg))
        else:
            expanded.append(seg)
    segments = expanded
    n = len(segments)
    used = [False] * n  # Track which segments are part of a take group
    result = []

    i = 0
    while i < n:
        if used[i]:
            i += 1
            continue

        seg = segments[i]
        if seg["action"] != "keep":
            result.append(seg)
            i += 1
            continue

        # Look ahead for similar segments
        group = [i]
        for j in range(i + 1, min(i + lookahead + 1, n)):
            if used[j] or segments[j]["action"] != "keep":
                continue
            if _prefix_matches(seg["text"], segments[j]["text"]):
                group.append(j)
            elif _text_similarity(seg["text"], segments[j]["text"]) > sim_threshold:
                group.append(j)

        if len(group) > 1:
            # Mark all as used
            for idx in group:
                used[idx] = True

            # Find the best take: last one that seems complete
            # (longest among the last few, or simply the last one)
            best_idx = group[-1]  # Default: keep last take
            best_seg = deepcopy(segments[best_idx])

            # Check if the last take is suspiciously short compared to others
            lengths = [(idx, len(segments[idx]["words"])) for idx in group]
            max_len = max(l for _, l in lengths)
            last_len = len(segments[best_idx]["words"])

            if last_len < max_len * 0.5 and len(group) > 2:
                # Last take seems incomplete — try the second-to-last
                alt_idx = group[-2]
                if len(segments[alt_idx]["words"]) > last_len:
                    best_idx = alt_idx
                    best_seg = deepcopy(segments[best_idx])

            best_seg["reason"] = f"kept take {group.index(best_idx) + 1}/{len(group)}"

            # Check for borderline similarity — flag for review
            for idx in group:
                if idx == best_idx:
                    continue
                sim = _text_similarity(segments[idx]["text"], segments[best_idx]["text"])
                if 0.4 <= sim <= 0.6:
                    best_seg["flags"].append(
                        f"⚠️ borderline similarity ({sim:.2f}) with cut segment at "
                        f"{segments[idx]['start']:.1f}s: \"{segments[idx]['text'][:80]}...\""
                    )

            result.append(best_seg)

            # Add cut entries for the others
            for idx in group:
                if idx == best_idx:
                    continue
                cut_seg = deepcopy(segments[idx])
                cut_seg["action"] = "cut"
                cut_seg["reason"] = f"repeated take ({group.index(idx) + 1}/{len(group)})"
                result.append(cut_seg)
        else:
            result.append(segments[i])

        i += 1

    # Sort by start time
    result.sort(key=lambda s: s["start"])
    return result


# ── Pass 3: Filler removal ──────────────────────────────────────────────────

def _is_filler_word(word_text, prev_text=None, next_text=None, is_entire_segment=False):
    """Check if a word is a filler (not 'like' meaning 'such as', etc.)."""
    w = word_text.lower().rstrip(".,!?;:")

    if w in ("um", "uh"):
        return True

    # "like" is a filler only when standalone or at phrase boundaries
    # Not when it means "such as" or "similar to"
    if w == "like":
        # Keep "like" if preceded by words suggesting comparison
        if prev_text and prev_text.lower().rstrip(".,!?;:") in ("looks", "sounds", "feels", "something", "more", "just"):
            return False
        return True

    return False


# Words that are fillers only when they are the entire segment (standalone after utterance split)
STANDALONE_FILLERS = {"yeah", "yes", "okay", "ok", "right", "well", "but", "so",
                      "alright", "anyway", "anyways"}


def _is_filler_bigram(w1_text, w2_text):
    """Check if two consecutive words form a filler bigram."""
    bigram = f"{w1_text.lower().rstrip('.,!?;:')} {w2_text.lower().rstrip('.,!?;:')}"
    return bigram in FILLER_BIGRAMS


def remove_fillers(segments):
    """Within each kept segment, split around filler words to create sub-clips.

    Also cuts segments that are entirely standalone filler words (e.g., "But", "yeah").
    """
    result = []

    for seg in segments:
        if seg["action"] != "keep":
            result.append(seg)
            continue

        words = seg["words"]
        if not words:
            result.append(seg)
            continue

        # Check if entire segment is a standalone filler (1-2 words)
        if len(words) <= 2:
            seg_text = " ".join(w["word"].lower().rstrip(".,!?;:") for w in words)
            if seg_text in STANDALONE_FILLERS or all(
                w["word"].lower().rstrip(".,!?;:") in STANDALONE_FILLERS | {"um", "uh"}
                for w in words
            ):
                cut_seg = deepcopy(seg)
                cut_seg["action"] = "cut"
                cut_seg["reason"] = f"standalone filler: \"{seg['text']}\""
                result.append(cut_seg)
                continue

        # Mark filler positions
        is_filler = [False] * len(words)

        # Check bigrams first (so we can mark both words)
        i = 0
        while i < len(words) - 1:
            if _is_filler_bigram(words[i]["word"], words[i + 1]["word"]):
                is_filler[i] = True
                is_filler[i + 1] = True
                i += 2
            else:
                i += 1

        # Check single fillers
        for i in range(len(words)):
            if is_filler[i]:
                continue
            prev_text = words[i - 1]["word"] if i > 0 else None
            next_text = words[i + 1]["word"] if i < len(words) - 1 else None
            if _is_filler_word(words[i]["word"], prev_text, next_text):
                is_filler[i] = True

        # Split into sub-clips around fillers
        current_words = []
        has_fillers = any(is_filler)

        for i, word in enumerate(words):
            if is_filler[i]:
                # Flush current non-filler words as a segment
                if current_words:
                    sub = make_segment(current_words, action="keep",
                                       reason=seg.get("reason", ""),
                                       flags=list(seg.get("flags", [])))
                    result.append(sub)
                    current_words = []
                # Add filler as a cut segment
                filler_seg = make_segment([word], action="cut",
                                          reason=f"filler: \"{word['word']}\"")
                if filler_seg:
                    result.append(filler_seg)
            else:
                current_words.append(word)

        # Flush remaining
        if current_words:
            sub = make_segment(current_words, action="keep",
                               reason=seg.get("reason", ""),
                               flags=list(seg.get("flags", [])))
            result.append(sub)
        elif not has_fillers:
            # No fillers found, keep original segment
            result.append(seg)

    return result


# ── Pass 4: Incomplete sentence trimming ─────────────────────────────────────

def trim_incomplete_sentences(segments):
    """Trim segments ending in dangling fillers or conjunctions."""
    result = []

    for seg in segments:
        if seg["action"] != "keep":
            result.append(seg)
            continue

        words = seg["words"]
        if not words or len(words) < 2:
            result.append(seg)
            continue

        # Trim trailing incomplete words
        trim_count = 0
        for j in range(len(words) - 1, -1, -1):
            w = words[j]["word"].lower().rstrip(".,!?;:")
            if w in TRAILING_INCOMPLETE:
                trim_count += 1
            else:
                break

        if trim_count > 0 and trim_count < len(words):
            kept_words = words[:len(words) - trim_count]
            trimmed_words = words[len(words) - trim_count:]

            kept_seg = make_segment(kept_words, action="keep",
                                    reason=seg.get("reason", ""),
                                    flags=list(seg.get("flags", [])))
            if kept_seg:
                result.append(kept_seg)

            trim_seg = make_segment(trimmed_words, action="cut",
                                    reason=f"incomplete trailing: \"{' '.join(w['word'] for w in trimmed_words)}\"")
            if trim_seg:
                result.append(trim_seg)
        else:
            result.append(seg)

    return result


# ── Pass 5: Silence normalization + padding ──────────────────────────────────

def normalize_silences(segments, target_gap=TARGET_GAP, min_gap=MIN_GAP):
    """Adjust segment boundaries to normalize inter-segment gaps.

    Only operates on 'keep' segments. Adjusts start/end times so that
    gaps between consecutive kept segments are within [min_gap, target_gap].
    """
    kept = [s for s in segments if s["action"] == "keep"]
    cuts = [s for s in segments if s["action"] != "keep"]

    if not kept:
        return segments

    # Sort kept segments by start time
    kept.sort(key=lambda s: s["start"])

    # Normalize gaps between consecutive kept segments
    for i in range(1, len(kept)):
        gap = kept[i]["start"] - kept[i - 1]["end"]
        if gap > target_gap:
            # Reduce gap by moving the start of the next segment earlier
            # But don't go earlier than min_gap after previous end
            new_start = kept[i - 1]["end"] + target_gap
            # Don't move start before the first word
            first_word_start = kept[i]["words"][0]["start"] if kept[i]["words"] else kept[i]["start"]
            kept[i]["start"] = min(new_start, first_word_start)
        elif gap < min_gap:
            # Ensure minimum gap
            kept[i]["start"] = kept[i - 1]["end"] + min_gap

    return kept + cuts


def apply_padding(segments, pre=PRE_PADDING, post=POST_PADDING,
                  pre_roll=PRE_ROLL, post_roll=POST_ROLL):
    """Apply padding around segments and pre/post roll to first/last segments."""
    kept = [s for s in segments if s["action"] == "keep"]
    cuts = [s for s in segments if s["action"] != "keep"]

    if not kept:
        return segments

    kept.sort(key=lambda s: s["start"])

    for i, seg in enumerate(kept):
        if not seg["words"]:
            continue

        first_word_start = seg["words"][0]["start"]
        last_word_end = seg["words"][-1]["end"]

        # Apply standard padding
        seg["start"] = first_word_start - pre
        seg["end"] = last_word_end + post

        # Pre-roll for first segment
        if i == 0:
            seg["start"] = max(0, first_word_start - pre_roll)

        # Post-roll for last segment
        if i == len(kept) - 1:
            seg["end"] = last_word_end + post_roll

    # Ensure no overlaps between consecutive kept segments
    for i in range(1, len(kept)):
        if kept[i]["start"] < kept[i - 1]["end"]:
            # Split the overlap: give preference to the earlier segment's post-padding
            midpoint = (kept[i - 1]["end"] + kept[i]["start"]) / 2
            kept[i - 1]["end"] = midpoint
            kept[i]["start"] = midpoint

    # Filter out segments that are too short
    kept = [s for s in kept if (s["end"] - s["start"]) >= MIN_SEGMENT_DURATION]

    return kept + cuts


# ── EDL builder ──────────────────────────────────────────────────────────────

def build_edl(segments, source_file, total_duration):
    """Build EDL JSON from processed segments."""
    kept = sorted([s for s in segments if s["action"] == "keep"],
                  key=lambda s: s["start"])

    edl_segments = []
    for i, seg in enumerate(kept):
        edl_seg = {
            "start": round(seg["start"], 3),
            "end": round(seg["end"], 3),
            "action": "keep",
            "label": f"Segment {i + 1}",
        }
        if seg.get("reason"):
            edl_seg["justification"] = seg["reason"]
        edl_segments.append(edl_seg)

    kept_duration = sum(s["end"] - s["start"] for s in edl_segments)

    return {
        "source_file": source_file,
        "total_duration": round(total_duration, 3),
        "kept_duration": round(kept_duration, 3),
        "retention_pct": round(kept_duration / total_duration * 100, 1) if total_duration > 0 else 0,
        "segment_count": len(edl_segments),
        "segments": edl_segments,
    }


# ── Review doc builder ───────────────────────────────────────────────────────

def _format_time(seconds):
    """Format seconds as mm:ss.s"""
    m = int(seconds // 60)
    s = seconds % 60
    return f"{m}:{s:04.1f}"


def build_review_doc(segments, source_file, total_duration):
    """Build a human-readable markdown review document."""
    kept = sorted([s for s in segments if s["action"] == "keep"],
                  key=lambda s: s["start"])
    cuts = sorted([s for s in segments if s["action"] != "keep"],
                  key=lambda s: s["start"])

    kept_duration = sum(s["end"] - s["start"] for s in kept)
    cut_duration = total_duration - kept_duration

    lines = []
    lines.append(f"# Edit Review: {Path(source_file).stem}")
    lines.append("")
    lines.append("## Stats")
    lines.append(f"- **Original duration:** {_format_time(total_duration)} ({total_duration:.1f}s)")
    lines.append(f"- **Kept duration:** {_format_time(kept_duration)} ({kept_duration:.1f}s)")
    lines.append(f"- **Retention:** {kept_duration / total_duration * 100:.1f}%")
    lines.append(f"- **Segments:** {len(kept)} kept, {len(cuts)} cut")
    lines.append("")

    # Flagged decisions
    flagged = [s for s in kept if s.get("flags")]
    if flagged:
        lines.append("## ⚠️ Flagged Decisions (review these)")
        lines.append("")
        for s in flagged:
            lines.append(f"### [{_format_time(s['start'])} – {_format_time(s['end'])}]")
            lines.append(f"> {s['text'][:200]}")
            for flag in s["flags"]:
                lines.append(f"- {flag}")
            lines.append("")

    # Kept segments
    lines.append("## Kept Segments")
    lines.append("")
    for i, s in enumerate(kept):
        dur = s["end"] - s["start"]
        lines.append(f"### {i + 1}. [{_format_time(s['start'])} – {_format_time(s['end'])}] ({dur:.1f}s)")
        lines.append(f"> {s['text']}")
        if s.get("reason"):
            lines.append(f"- *{s['reason']}*")
        lines.append("")

    # Cut summary by reason
    lines.append("## Cut Summary")
    lines.append("")
    reason_groups = {}
    for s in cuts:
        reason = s.get("reason", "unspecified")
        # Categorize
        if "repeated take" in reason:
            cat = "Repeated takes"
        elif "filler" in reason:
            cat = "Filler words"
        elif "incomplete" in reason:
            cat = "Incomplete sentences"
        elif "silence" in reason:
            cat = "Silence"
        else:
            cat = "Other"
        if cat not in reason_groups:
            reason_groups[cat] = []
        reason_groups[cat].append(s)

    for cat, segs in sorted(reason_groups.items()):
        total_cat_dur = sum(s["end"] - s["start"] for s in segs)
        lines.append(f"### {cat} ({len(segs)} cuts, {total_cat_dur:.1f}s)")
        for s in segs[:10]:  # Show first 10
            dur = s["end"] - s["start"]
            text_preview = s["text"][:100]
            lines.append(f"- [{_format_time(s['start'])}] ({dur:.1f}s) \"{text_preview}\"")
        if len(segs) > 10:
            lines.append(f"- ... and {len(segs) - 10} more")
        lines.append("")

    return "\n".join(lines)


# ── Pipeline ─────────────────────────────────────────────────────────────────

def propose_edits(analysis_path, output_dir=None):
    """Run the full edit proposal pipeline.

    Args:
        analysis_path: Path to <stem>_analysis.json
        output_dir: Directory for outputs (default: same as analysis file)

    Returns:
        (edl_path, review_path) tuple
    """
    with open(analysis_path) as f:
        analysis = json.load(f)

    words = analysis["transcript"]["words"]
    source_file = analysis["source_file"]
    total_duration = analysis["metadata"]["duration"]
    stem = Path(source_file).stem

    if output_dir is None:
        output_dir = os.path.dirname(analysis_path)
    os.makedirs(output_dir, exist_ok=True)

    print(f"Proposing edits for: {stem}")
    print(f"  {len(words)} words, {total_duration:.1f}s total duration")

    # Pass 1: Segment utterances
    print("\n[1/5] Segmenting utterances...")
    segments = segment_utterances(words)
    print(f"  {len(segments)} utterances")

    # Pass 2: Detect repeated takes
    print("[2/5] Detecting repeated takes...")
    segments = detect_repeated_takes(segments)
    kept_count = sum(1 for s in segments if s["action"] == "keep")
    cut_count = sum(1 for s in segments if s["action"] != "keep")
    print(f"  {kept_count} kept, {cut_count} cut as repeats")

    # Pass 3: Remove fillers
    print("[3/5] Removing fillers...")
    segments = remove_fillers(segments)
    kept_count = sum(1 for s in segments if s["action"] == "keep")
    print(f"  {kept_count} kept segments after filler removal")

    # Pass 4: Trim incomplete sentences
    print("[4/5] Trimming incomplete sentences...")
    segments = trim_incomplete_sentences(segments)
    kept_count = sum(1 for s in segments if s["action"] == "keep")
    print(f"  {kept_count} kept segments after trimming")

    # Pass 5: Normalize silences + padding
    print("[5/5] Normalizing silences and applying padding...")
    segments = normalize_silences(segments)
    segments = apply_padding(segments)
    kept_count = sum(1 for s in segments if s["action"] == "keep")
    print(f"  {kept_count} final kept segments")

    # Build outputs
    edl = build_edl(segments, source_file, total_duration)
    review = build_review_doc(segments, source_file, total_duration)

    edl_path = os.path.join(output_dir, f"{stem}_edl.json")
    review_path = os.path.join(output_dir, f"{stem}_review.md")

    with open(edl_path, "w") as f:
        json.dump(edl, f, indent=2)
    print(f"\nEDL written to {edl_path}")

    with open(review_path, "w") as f:
        f.write(review)
    print(f"Review written to {review_path}")

    print(f"\nSummary:")
    print(f"  Original: {_format_time(total_duration)} ({total_duration:.1f}s)")
    print(f"  Kept:     {_format_time(edl['kept_duration'])} ({edl['kept_duration']:.1f}s)")
    print(f"  Retention: {edl['retention_pct']}%")
    print(f"  Segments: {edl['segment_count']}")

    flagged = sum(1 for s in segments if s["action"] == "keep" and s.get("flags"))
    if flagged:
        print(f"  ⚠️ {flagged} segments flagged for review")

    return edl_path, review_path


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
    if len(sys.argv) < 2:
        print("Usage: uv run propose_edits.py <analysis_json> [--output-dir <dir>]")
        sys.exit(1)

    analysis_path = sys.argv[1]
    output_dir = None

    args = sys.argv[2:]
    i = 0
    while i < len(args):
        if args[i] == "--output-dir" and i + 1 < len(args):
            output_dir = args[i + 1]
            i += 2
        else:
            i += 1

    if output_dir is None:
        # Default to same directory as analysis file
        output_dir = os.path.dirname(os.path.abspath(analysis_path))

    propose_edits(analysis_path, output_dir)
