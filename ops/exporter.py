#!/usr/bin/env python3
"""LibraLink request logger (runs every minute from libralink-exporter.timer).

LibreChat saves every question and answer in MongoDB. This script reads the answers
saved since its last run and writes ONE JSON LINE PER ANSWER to
/var/log/libralink/requests.log. The CloudWatch agent ships that file to the log group
/libralink/requests, where metric filters turn the lines into the custom metrics
AnswersTotal, AnswersFailed, EmptyAnswer, NotFound, AnswerDurationMs and PIIFlagged.

Each line records what the brief asks for: the question asked, how long it took,
whether it succeeded, and which version answered (model + app version + content hash).

Privacy: if a question looks like it contains personal data (email, phone, ID-like
number), the question text is NOT logged - it is replaced with a redaction note and
pii_flag is set to true, which raises the PIIFlagged alarm.

Standard library only. It talks to MongoDB with `docker exec ... mongosh`, so the
database port never has to be opened.
"""
import datetime as dt
import hashlib
import json
import pathlib
import re
import subprocess
import sys

LOG_FILE = pathlib.Path("/var/log/libralink/requests.log")
STATE_FILE = pathlib.Path("/var/lib/libralink/exporter-state.json")
VERSION_FILE = pathlib.Path("/opt/libralink/run/version.json")
MONGO_CONTAINER = "chat-mongodb"
NOT_FOUND = "couldn't find that in the libralink handbook"

PII_PATTERNS = [
    re.compile(r"[\w.+-]+@[\w-]+\.[\w.-]+"),             # email address
    re.compile(r"(\+?63|0)9\d{2}[\s-]?\d{3}[\s-]?\d{4}"),  # PH mobile number
    re.compile(r"\b\d{2,4}-\d{4,6}(-\d{2,4})?\b"),          # student/employee ID-like number
    re.compile(r"\b\d{9,}\b"),                              # any long number (IDs, accounts)
]

# Runs inside the MongoDB container. SINCE is filled in by Python (an ISO date we control).
MONGO_JS = r"""
const since = new Date(SINCE);
function textOf(m) {
  if (!m) return '';
  if (typeof m.text === 'string' && m.text.length) return m.text;
  if (Array.isArray(m.content)) {
    return m.content.filter(c => c && c.type === 'text')
      .map(c => typeof c.text === 'string' ? c.text : (c.text && c.text.value) || '').join('\n');
  }
  return '';
}
db.messages.find({ isCreatedByUser: false, createdAt: { $gt: since } })
  .sort({ createdAt: 1 }).limit(500).forEach(m => {
    const p = m.parentMessageId ? db.messages.findOne({ messageId: m.parentMessageId }) : null;
    const a = textOf(m);
    const hasErrorPart = Array.isArray(m.content) && m.content.some(c => c && c.type === 'error');
    print(JSON.stringify({
      id: m.messageId, conv: m.conversationId || '',
      created: m.createdAt, updated: m.updatedAt || m.createdAt,
      qcreated: p ? p.createdAt : null, q: textOf(p),
      a_len: a.length, a_head: a.slice(0, 400),
      error: !!m.error || hasErrorPart, unfinished: !!m.unfinished,
      model: m.model || null
    }));
  });
"""


def parse_time(s):
    if not s:
        return None
    return dt.datetime.fromisoformat(s.replace("Z", "+00:00"))


def load_state():
    try:
        return json.loads(STATE_FILE.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        # First run: only look back 10 minutes so old local test chats are not counted.
        start = dt.datetime.now(dt.timezone.utc) - dt.timedelta(minutes=10)
        return {"since": start.isoformat(timespec="milliseconds").replace("+00:00", "Z")}


def main():
    state = load_state()
    try:
        version = json.loads(VERSION_FILE.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        version = {}

    js = f"const SINCE = {json.dumps(state['since'])};\n" + MONGO_JS
    try:
        out = subprocess.run(
            ["docker", "exec", MONGO_CONTAINER, "mongosh", "LibreChat", "--quiet", "--eval", js],
            capture_output=True, text=True, timeout=40, check=True,
        ).stdout
    except (subprocess.SubprocessError, FileNotFoundError) as e:
        # The database being down is itself worth a log line (the app is broken).
        write([{"ts": now_iso(), "event": "exporter_error", "error": str(e)[:300]}])
        sys.exit(1)

    lines, newest = [], state["since"]
    for raw in out.splitlines():
        raw = raw.strip()
        if not raw.startswith("{"):
            continue
        m = json.loads(raw)
        end = parse_time(m["updated"]) or parse_time(m["created"])
        startq = parse_time(m["qcreated"])
        duration_ms = int((end - startq).total_seconds() * 1000) if (end and startq) else None

        question = m["q"] or ""
        pii = any(p.search(question) for p in PII_PATTERNS)
        empty = m["a_len"] == 0
        not_found = NOT_FOUND in m["a_head"].lower().replace("’", "'")
        success = (not m["error"]) and (not m["unfinished"]) and (not empty)

        lines.append({
            "ts": m["updated"] or m["created"],
            "event": "answer",
            "message_id": m["id"],
            # Conversation id is hashed so log readers cannot open someone's chat.
            "conversation": hashlib.sha256(m["conv"].encode()).hexdigest()[:10],
            "question": "[redacted: possible personal data]" if pii else question[:300],
            "question_chars": len(question),
            "answer_chars": m["a_len"],
            "duration_ms": duration_ms,
            "success": success,
            "empty": empty,
            "not_found": not_found,
            "error": m["error"],
            "model": m["model"] or version.get("model"),
            "app_version": version.get("app_version"),
            "content_hash": version.get("content_hash"),
            "pii_flag": pii,
        })
        if m["created"] > newest:
            newest = m["created"]

    write(lines)
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text(json.dumps({"since": newest}))
    print(f"logged {len(lines)} answer(s); next run starts after {newest}")


def now_iso():
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def write(records):
    if not records:
        return
    LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
    with LOG_FILE.open("a", encoding="utf-8") as f:
        for r in records:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    main()
