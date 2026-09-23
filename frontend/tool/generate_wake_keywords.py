#!/usr/bin/env python3
"""Regenerate assets/wake/keywords.txt from wake_phrases.json.

Requires sherpa-onnx 1.13.8's `sherpa-onnx-cli` and pypinyin. The matching
English phone lexicon is downloaded from the official KWS model release unless
`--model-dir` or `SHERPA_KWS_MODEL_DIR` points at an extracted model.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import urllib.request


MODEL_NAME = "sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20"
MODEL_URL = (
    "https://github.com/k2-fsa/sherpa-onnx/releases/download/kws-models/"
    f"{MODEL_NAME}.tar.bz2"
)
FRONTEND = Path(__file__).resolve().parents[1]
MANIFEST = FRONTEND / "assets" / "wake" / "wake_phrases.json"
TOKENS = FRONTEND / "assets" / "wake" / "model" / "tokens.txt"
OUTPUT = FRONTEND / "assets" / "wake" / "keywords.txt"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--model-dir",
        type=Path,
        default=os.environ.get("SHERPA_KWS_MODEL_DIR"),
        help=f"Extracted {MODEL_NAME} directory (avoids the one-time download)",
    )
    parser.add_argument(
        "--sherpa-cli",
        default=shutil.which("sherpa-onnx-cli"),
        help="Path to sherpa-onnx-cli",
    )
    return parser.parse_args()


def download_lexicon(destination: Path) -> Path:
    archive = destination / f"{MODEL_NAME}.tar.bz2"
    print(f"Downloading phone lexicon from {MODEL_URL}")
    urllib.request.urlretrieve(MODEL_URL, archive)
    member_name = f"{MODEL_NAME}/en.phone"
    with tarfile.open(archive, "r:bz2") as bundle:
        member = bundle.getmember(member_name)
        source = bundle.extractfile(member)
        if source is None:
            raise RuntimeError(f"{member_name} is missing from the model archive")
        lexicon = destination / "en.phone"
        with lexicon.open("wb") as target:
            shutil.copyfileobj(source, target)
    return lexicon


def phrase_rows() -> list[tuple[str, str]]:
    data = json.loads(MANIFEST.read_text(encoding="utf-8"))
    rows: list[tuple[str, str]] = []
    seen: set[str] = set()
    for item in data.get("phrases", []):
        phrase = str(item.get("phrase", "")).strip()
        phrase_id = str(item.get("id", "")).strip()
        if not phrase and item.get("enabled") is False:
            continue
        if not phrase or not phrase_id:
            raise ValueError("Each non-placeholder phrase needs both id and phrase")
        if phrase_id in seen or any(character.isspace() for character in phrase_id):
            raise ValueError(f"Invalid or duplicate phrase id: {phrase_id!r}")
        seen.add(phrase_id)
        rows.append((phrase, phrase_id))
    return rows


def main() -> None:
    args = parse_args()
    if not args.sherpa_cli:
        raise SystemExit(
            "sherpa-onnx-cli was not found. Install sherpa-onnx==1.13.8 and pypinyin first."
        )
    if not TOKENS.is_file():
        raise SystemExit(f"Missing bundled model tokens: {TOKENS}")

    with tempfile.TemporaryDirectory(prefix="kora-wake-keywords-") as scratch:
        scratch_path = Path(scratch)
        model_dir = Path(args.model_dir) if args.model_dir else None
        lexicon = model_dir / "en.phone" if model_dir else download_lexicon(scratch_path)
        if not lexicon.is_file():
            raise SystemExit(f"Missing English phone lexicon: {lexicon}")

        rows = phrase_rows()
        raw = scratch_path / "keywords_raw.txt"
        generated = scratch_path / "keywords.txt"
        raw.write_text(
            "".join(f"{phrase.upper()} @{phrase_id}\n" for phrase, phrase_id in rows),
            encoding="utf-8",
        )
        subprocess.run(
            [
                args.sherpa_cli,
                "text2token",
                "--tokens",
                str(TOKENS),
                "--tokens-type",
                "phone+ppinyin",
                "--lexicon",
                str(lexicon),
                str(raw),
                str(generated),
            ],
            check=True,
        )
        lines = [line.strip() for line in generated.read_text(encoding="utf-8").splitlines()]
        if len(lines) != len(rows) or any(not line for line in lines):
            raise RuntimeError("sherpa text2token did not produce one line per phrase")
        expected_labels = [f"@{phrase_id}" for _, phrase_id in rows]
        actual_labels = [line.split()[-1] for line in lines]
        if actual_labels != expected_labels:
            raise RuntimeError("sherpa text2token changed or omitted a phrase label")

        temporary_output = OUTPUT.with_suffix(".txt.tmp")
        temporary_output.write_text("\n".join(lines) + "\n", encoding="utf-8")
        temporary_output.replace(OUTPUT)
        print(f"Wrote {len(lines)} tokenized phrases to {OUTPUT.relative_to(FRONTEND)}")


if __name__ == "__main__":
    main()
