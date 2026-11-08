#!/usr/bin/env python3
"""Score LibraLink Desk on the 30 labelled questions in eval/questions.json (WS-A items 8-9).

It sends each question to the SAME Gemini model with the SAME system prompt and handbook the
app uses (built by ops/render_config.py), at the same temperature (0.2), and checks the answer
against the expected phrases. Calling the model directly (not through the web page) keeps the
test repeatable; the trade-off is that it does not test the LibreChat page itself - that is what
the three manual test questions and the health check are for.

Run on the server (it reads the key from Parameter Store, so it never appears on screen):
    sudo python3 /opt/libralink/eval/eval.py
Options:
    --limit 5            only the first 5 questions
    --delay 7            seconds between calls (free tier allows only a few calls per minute)
    --list-models        show the models your key can use, then stop
Writes eval/results/eval-<timestamp>.csv and prints the score.
Standard library only.
"""
import argparse
import csv
import datetime as dt
import json
import os
import pathlib
import subprocess
import sys
import time
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "ops"))
from render_config import build_prompt  # noqa: E402  (same prompt as the app)

API = "https://generativelanguage.googleapis.com/v1beta"


def region():
    """Region from the environment, or from the EC2 metadata service (IMDSv2)."""
    if os.environ.get("AWS_REGION"):
        return os.environ["AWS_REGION"]
    tok = urllib.request.urlopen(urllib.request.Request(
        "http://169.254.169.254/latest/api/token", method="PUT",
        headers={"X-aws-ec2-metadata-token-ttl-seconds": "60"}), timeout=3).read().decode()
    return urllib.request.urlopen(urllib.request.Request(
        "http://169.254.169.254/latest/meta-data/placement/region",
        headers={"X-aws-ec2-metadata-token": tok}), timeout=3).read().decode()


def ssm(name, decrypt=False):
    cmd = ["aws", "ssm", "get-parameter", "--region", region(), "--name", name,
           "--query", "Parameter.Value", "--output", "text"]
    if decrypt:
        cmd.append("--with-decryption")
    return subprocess.check_output(cmd, text=True).strip()


def call(url, key, body=None):
    req = urllib.request.Request(url, data=json.dumps(body).encode() if body else None,
                                 headers={"x-goog-api-key": key, "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read())


def ask(model, key, system_prompt, question, retries=3):
    body = {
        "systemInstruction": {"parts": [{"text": system_prompt}]},
        "contents": [{"role": "user", "parts": [{"text": question}]}],
        "generationConfig": {"temperature": 0.2},
    }
    for attempt in range(retries):
        try:
            start = time.time()
            data = call(f"{API}/models/{model}:generateContent", key, body)
            parts = data.get("candidates", [{}])[0].get("content", {}).get("parts", [])
            text = "".join(p.get("text", "") for p in parts if not p.get("thought"))
            return text, int((time.time() - start) * 1000), ""
        except urllib.error.HTTPError as e:
            if e.code == 429 and attempt < retries - 1:   # rate limited: wait and try again
                time.sleep(30)
                continue
            return "", 0, f"HTTP {e.code}"
        except Exception as e:  # noqa: BLE001
            return "", 0, str(e)[:100]
    return "", 0, "gave up"


def norm(s):
    return s.lower().replace("’", "'").replace("‘", "'")


def score(answer, q):
    a = norm(answer)
    ok_any = any(norm(p) in a for p in q["must_include_any"])
    bad = [p for p in q.get("must_not_include", []) if norm(p) in a]
    return ok_any and not bad


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--delay", type=float, default=7)
    ap.add_argument("--content", default=str(ROOT / "run" / "content"))
    ap.add_argument("--list-models", action="store_true")
    args = ap.parse_args()

    key = os.environ.get("GOOGLE_KEY") or ssm("/libralink/secret/GOOGLE_KEY", decrypt=True)
    if args.list_models:
        for m in call(f"{API}/models?pageSize=200", key).get("models", []):
            if "generateContent" in m.get("supportedGenerationMethods", []):
                print(m["name"].removeprefix("models/"))
        return

    model = os.environ.get("GOOGLE_MODEL") or ssm("/libralink/config/GOOGLE_MODEL")
    content_dir = pathlib.Path(args.content)
    if not content_dir.exists():
        content_dir = ROOT / "content"
    system_prompt, content_hash = build_prompt(content_dir)

    questions = json.loads((ROOT / "eval" / "questions.json").read_text())["questions"]
    if args.limit:
        questions = questions[: args.limit]

    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    out_dir = ROOT / "eval" / "results"
    out_dir.mkdir(exist_ok=True)
    out_file = out_dir / f"eval-{stamp}.csv"

    rows, passed = [], 0
    for i, q in enumerate(questions):
        answer, ms, err = ask(model, key, system_prompt, q["question"])
        ok = (not err) and score(answer, q)
        passed += ok
        rows.append({"id": q["id"], "category": q["category"], "pass": ok, "ms": ms, "error": err,
                     "question": q["question"], "answer": answer.replace("\n", " ")[:500]})
        print(f"{q['id']} {'PASS' if ok else 'FAIL'} {ms:>6} ms  {q['question'][:60]}")
        if i < len(questions) - 1:
            time.sleep(args.delay)

    with out_file.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)

    by_cat = {}
    for r in rows:
        c = by_cat.setdefault(r["category"], [0, 0])
        c[0] += r["pass"]
        c[1] += 1
    print()
    print(f"RESULT: {passed}/{len(rows)} correct ({100 * passed / len(rows):.0f}%)  "
          f"model={model} content={content_hash} date={stamp}")
    for c, (p, n) in by_cat.items():
        print(f"  {c:<17} {p}/{n}")
    print(f"Details: {out_file}")


if __name__ == "__main__":
    main()
