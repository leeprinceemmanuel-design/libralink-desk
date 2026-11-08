#!/usr/bin/env python3
"""Build app/librechat.yaml from the template, the system prompt and the handbook files.

Usage:
  python3 ops/render_config.py --content <folder with .md files> --model <gemini model> --site <site url>

Also writes run/version.json (content hash + app version) so the request logger
can record which version of the content answered each question.
Only the Python standard library is used, so it runs on Amazon Linux and in a
plain python container without installing anything.
"""
import argparse
import hashlib
import json
import os
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent


def build_handbook(content_dir: pathlib.Path) -> tuple[str, str]:
    files = sorted(p for p in content_dir.glob("*.md") if p.is_file())
    if not files:
        # Fail loudly: an assistant with no handbook would answer "I couldn't find that" to everything.
        sys.exit(f"ERROR: no .md handbook files found in {content_dir}")
    parts, digest = [], hashlib.sha256()
    for f in files:
        text = f.read_text(encoding="utf-8").strip()
        digest.update(f.name.encode() + b"\0" + text.encode())
        parts.append(f"=== file: {f.name} ===\n{text}")
    return "\n\n".join(parts), digest.hexdigest()[:12]


def build_prompt(content_dir: pathlib.Path) -> tuple[str, str]:
    """Shared with eval/eval.py so the evaluation uses the exact same prompt as the app."""
    handbook, content_hash = build_handbook(content_dir)
    prompt = (ROOT / "app" / "system-prompt.txt").read_text(encoding="utf-8")
    prompt = prompt.replace("__CONTENT_HASH__", content_hash).replace("__HANDBOOK__", handbook)
    return prompt, content_hash


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--content", required=True)
    ap.add_argument("--model", required=True)
    ap.add_argument("--site", required=True, help="project website URL, no trailing slash")
    ap.add_argument("--app-version", default=os.environ.get("APP_VERSION", "dev"))
    ap.add_argument("--out", default=str(ROOT / "app" / "librechat.yaml"))
    args = ap.parse_args()

    prompt, content_hash = build_prompt(pathlib.Path(args.content))
    # promptPrefix is a YAML block scalar (|) nested 10 spaces deep, so every line is indented 10 spaces.
    indented = "\n".join(("          " + line) if line.strip() else "" for line in prompt.splitlines())

    tmpl = (ROOT / "app" / "librechat.yaml.tmpl").read_text(encoding="utf-8")
    out = (tmpl.replace("__GOOGLE_MODEL__", args.model)
               .replace("__SITE_URL__", args.site.rstrip("/"))
               .replace("__PROMPT__", indented))
    pathlib.Path(args.out).write_text(out + "\n", encoding="utf-8")

    run_dir = ROOT / "run"
    run_dir.mkdir(exist_ok=True)
    (run_dir / "version.json").write_text(json.dumps({
        "app_version": args.app_version,
        "content_hash": content_hash,
        "model": args.model,
    }) + "\n", encoding="utf-8")
    print(f"wrote {args.out} (content {content_hash}, model {args.model}, version {args.app_version})")


if __name__ == "__main__":
    main()
