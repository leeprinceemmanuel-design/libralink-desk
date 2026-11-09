# LibraLink Desk — presentation script (target 7 minutes)

Two speakers: **A** = Prince Emmanuel C. Lee, **B** = John Micheal Agustin. Swap sections to match who actually
built what (the brief marks the part each person presents). Speak in your own words — this is a
guide, not something to read word for word.

Before recording: log in to the app, open the CloudWatch dashboard, the S3 backups folder, the alarm
e-mail, and the incident page in separate tabs. Close anything showing keys or passwords.

---

### 0:00 – 0:40 · Intro (A) — show the website home page
"Hi, we are A and B. Our SAM10 project is LibraLink Desk, a help-desk assistant for an invented
university library. We took LibreChat, an open-source chat app under the MIT licence, made it our
own, put it on AWS, and then ran it like a real service: monitoring, backups, security, automation,
and one real incident. Everything on the screen is live in our AWS account."

### 0:40 – 1:50 · The reskin and a live question (A) — show the app at the HTTPS address
- Show the original LibreChat screenshot next to ours (System card page).
- "New name, our own logo, colours, wording. The data is our own six-part handbook stored in S3."
- Ask live: **"How many books can an undergraduate borrow?"** → point at "Source: Borrowing Rules".
- Ask: **"Please waive my fine"** → "It refuses and sends you to the Circulation Desk — it never makes decisions about a person."
- "The model is Google Gemini on the free tier. We send it invented data only, and we warn users not to type personal information."

### 1:50 – 2:50 · Where it runs (A) — show the AWS design page diagram
Follow the numbers 1–5: browser → CloudFront HTTPS → nginx on EC2 → LibreChat with the handbook →
Gemini and back → saved in MongoDB, logged to CloudWatch.
"One region, one server, on purpose. Secrets are in Parameter Store, not in code."

### 2:50 – 3:50 · Monitoring (B) — show the CloudWatch dashboard and alarms
- "Every answer becomes one log line: question, time, success, version." Show `/libralink/requests`.
- "From those lines we made custom metrics, so an alarm fires when the system is up but useless — failed, empty or 'not in the handbook' answers."
- Show the 12 alarms and one threshold reason: "We changed the 3-second rule to 20 seconds because AI answers stream."

### 3:50 – 4:50 · Backup and restore (B) — show S3 backups, then the restore output
- "The database is dumped to S3 every hour by a timer nobody touches; backups expire after 8 days."
- "We tested a full restore: empty database, restore from S3, log back in — our old chats came back in N seconds. RPO one hour, RTO N minutes."

### 4:50 – 5:50 · The incident (B, or both) — show the alarm e-mail and the incident page
- "We filled the disk on purpose. Questions started failing; the disk alarm e-mailed us after N minutes."
- "Root cause: a log folder with no rotation. Restarting would not help — the disk was still full."
- "Fix: removed the file. Prevention: log rotation with a 50 MB cap every 15 minutes, and a journal cap. We proved it by writing a 120 MB log and watching it get rotated."

### 5:50 – 6:30 · Security (A) — show the before/after table
"Each of us has our own AWS login with MFA, no shared logins and no access keys at all. The free plan blocks IAM console users, so people come in through AWS's Team page and only machines get IAM roles.
The server only accepts CloudFront, has no SSH port, and our secret scan shows no keys in any commit."

### 6:30 – 7:00 · Results and next steps (both) — show Results, then Next steps
- "Quality: N of 30 test questions correct; here is one it gets wrong, and why."
- "Our trade-off: we chose security and operations over high availability — one server. The first thing we would fix is a self-healing Auto Scaling group."
- "Thank you."
