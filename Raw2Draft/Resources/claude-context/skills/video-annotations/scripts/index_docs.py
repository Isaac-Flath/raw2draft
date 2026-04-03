#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "requests",
#     "pymupdf",
# ]
# ///
"""Index a PDF into Mixedbread vector store for semantic search.

Usage:
    uv run scripts/index_docs.py <pdf_path> [--collection <name>]
    uv run scripts/index_docs.py --search "how to create outline stroke from mask"

Chunks the PDF into paragraphs, uploads to Mixedbread vector store.
"""

import json
import os
import sys
from pathlib import Path

import fitz  # pymupdf
import requests


def get_config():
    """Load API key and store ID from environment or .env file."""
    api_key = os.environ.get("MIXEDBREAD_API_KEY")
    store_id = os.environ.get("MIXEDBREAD_STORE_ID")

    if not api_key or not store_id:
        env_path = Path(__file__).parent.parent.parent.parent / ".env"
        if env_path.exists():
            for line in env_path.read_text().splitlines():
                if line.startswith("MIXEDBREAD_API_KEY="):
                    api_key = api_key or line.split("=", 1)[1].strip()
                elif line.startswith("MIXEDBREAD_STORE_ID="):
                    store_id = store_id or line.split("=", 1)[1].strip()

    if not api_key:
        print("ERROR: MIXEDBREAD_API_KEY not found", file=sys.stderr)
        sys.exit(1)
    if not store_id:
        print("ERROR: MIXEDBREAD_STORE_ID not found", file=sys.stderr)
        sys.exit(1)

    return api_key, store_id


def extract_chunks(pdf_path: str, chunk_size: int = 1500, overlap: int = 200) -> list[dict]:
    """Extract text chunks from a PDF with page numbers."""
    doc = fitz.open(pdf_path)
    chunks = []

    for page_num in range(len(doc)):
        page = doc[page_num]
        text = page.get_text()
        if not text.strip():
            continue

        # Split into paragraphs
        paragraphs = [p.strip() for p in text.split("\n\n") if p.strip()]

        # Combine small paragraphs into chunks of target size
        current_chunk = ""
        for para in paragraphs:
            if len(current_chunk) + len(para) > chunk_size and current_chunk:
                chunks.append({
                    "text": current_chunk.strip(),
                    "page": page_num + 1,
                    "source": Path(pdf_path).name,
                })
                # Keep overlap
                words = current_chunk.split()
                overlap_words = words[-overlap // 5:] if len(words) > overlap // 5 else []
                current_chunk = " ".join(overlap_words) + "\n\n" + para
            else:
                current_chunk += "\n\n" + para if current_chunk else para

        if current_chunk.strip():
            chunks.append({
                "text": current_chunk.strip(),
                "page": page_num + 1,
                "source": Path(pdf_path).name,
            })

    doc.close()
    return chunks


def upload_chunks(chunks: list[dict], api_key: str, store_id: str, collection: str = "fusion-docs"):
    """Upload text chunks to Mixedbread vector store."""
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
    }
    base_url = "https://api.mixedbread.com/v2"

    uploaded = 0
    # Upload in batches of 20
    batch_size = 20
    for i in range(0, len(chunks), batch_size):
        batch = chunks[i:i + batch_size]
        documents = []
        for j, chunk in enumerate(batch):
            documents.append({
                "content": {
                    "type": "text",
                    "text": chunk["text"],
                },
                "metadata": {
                    "page": chunk["page"],
                    "source": chunk["source"],
                    "collection": collection,
                    "chunk_index": i + j,
                },
            })

        resp = requests.post(
            f"{base_url}/vector_stores/{store_id}/documents",
            headers=headers,
            json={"documents": documents},
        )

        if resp.status_code in (200, 201):
            uploaded += len(batch)
            print(f"  Uploaded {uploaded}/{len(chunks)} chunks", file=sys.stderr)
        else:
            print(f"  ERROR uploading batch: {resp.status_code} {resp.text}", file=sys.stderr)

    return uploaded


def search(query: str, api_key: str, store_id: str, top_k: int = 5, collection: str = None) -> list[dict]:
    """Semantic search over the vector store."""
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
    }

    body = {
        "query": query,
        "top_k": top_k,
    }
    if collection:
        body["filters"] = {"metadata.collection": {"$eq": collection}}

    resp = requests.post(
        f"https://api.mixedbread.com/v2/vector_stores/{store_id}/search",
        headers=headers,
        json=body,
    )

    if resp.status_code != 200:
        print(f"Search error: {resp.status_code} {resp.text}", file=sys.stderr)
        return []

    data = resp.json()
    results = []
    for item in data.get("data", []):
        doc = item.get("document", {})
        content = doc.get("content", [{}])
        text = content[0].get("text", "") if isinstance(content, list) else content.get("text", "")
        metadata = doc.get("metadata", {})
        results.append({
            "text": text,
            "page": metadata.get("page", "?"),
            "source": metadata.get("source", "?"),
            "score": item.get("score", 0),
        })

    return results


def main():
    api_key, store_id = get_config()

    if "--search" in sys.argv:
        idx = sys.argv.index("--search")
        query = sys.argv[idx + 1]
        collection = None
        if "--collection" in sys.argv:
            cidx = sys.argv.index("--collection")
            collection = sys.argv[cidx + 1]

        results = search(query, api_key, store_id, collection=collection)
        for r in results:
            print(f"\n--- Page {r['page']} (score: {r['score']:.3f}) ---")
            print(r["text"][:500])
        return

    if len(sys.argv) < 2:
        print("Usage:")
        print('  index_docs.py <pdf_path> [--collection <name>]')
        print('  index_docs.py --search "query" [--collection <name>]')
        sys.exit(1)

    pdf_path = sys.argv[1]
    collection = "fusion-docs"
    if "--collection" in sys.argv:
        cidx = sys.argv.index("--collection")
        collection = sys.argv[cidx + 1]

    print(f"Extracting chunks from {pdf_path}...", file=sys.stderr)
    chunks = extract_chunks(pdf_path)
    print(f"  {len(chunks)} chunks extracted", file=sys.stderr)

    print(f"Uploading to Mixedbread store {store_id[:8]}... (collection: {collection})", file=sys.stderr)
    uploaded = upload_chunks(chunks, api_key, store_id, collection)
    print(f"Done! {uploaded} chunks indexed.", file=sys.stderr)


if __name__ == "__main__":
    main()
