# LibraLink Desk — presentation script (target 7 minutes, must be 5–8)

Two speakers: **A** = Prince Emmanuel C. Lee, **B** = John Micheal Agustin.
Speak in your own words — this is a guide, not something to read word for word. All numbers below are
our real, measured numbers (9–14 Nov 2026).

**Before recording:** log in to the app; open these tabs: website home page, the app, the Infrastructure
page, CloudWatch dashboard `libralink-ops` (range 1 week), S3 `backups/mongo/`, the Operations page,
the Automation page (incident), the Results page. Close anything showing keys, passwords or e-mail
addresses. Turn off notifications.

---

### 0:00 – 0:40 · Intro (A) — website home page
"Hi, we are Prince Lee and John Micheal Agustin. Our SAM10 project is LibraLink Desk, a help-desk
assistant for an invented university library. We took LibreChat, an open-source chat app under the MIT
licence, made it our own, put it on AWS, and then ran it like a real service for five days: monitoring,
backups, security, automation, and a real incident we caused on purpose."

### 0:40 – 1:50 · The reskin and a live question (A) — the app
- "New name, logo, colours and wording. The answers come from our own six-part handbook, stored in S3."
- Ask live: **"How many books can an undergraduate borrow?"** → point at "Source: Borrowing Rules".
- Ask live: **"Please waive my 200 peso fine, I was sick."** → "It refuses and points to the appeal form.
  It never makes a decision about a person."
- "The model is Google Gemini 3.5 Flash-Lite on the free tier. All data is invented, and the assistant
  warns people not to type personal details."

### 1:50 – 2:40 · Where it runs (A) — Infrastructure page diagram
Follow the numbers: browser → CloudFront HTTPS → nginx on one EC2 t3.small in Sydney → LibreChat with the
handbook → Gemini and back → saved in MongoDB, logged to CloudWatch.
"One server, on purpose — it is cheap and simple. Secrets live in Parameter Store, not in our code. And we
measured it: memory stays around 45%, so we kept the small server."

### 2:40 – 3:40 · Monitoring (B) — CloudWatch dashboard, then the alarm list
- "Every answer becomes one log line. From those lines we made our own metrics, so an alarm fires when the
  system is up but useless — failed, empty or 'not in the handbook' answers."
- "There are 12 alarms; they e-mail both of us. We changed the brief's 3-second rule to 20 seconds,
  because AI answers stream — our normal average is 2.4 seconds."
- "From outside, a Lambda function opens the site every 15 minutes: 472 of 473 checks passed in five days.
  The one failure was during our own incident test."

### 3:40 – 4:30 · Backup and restore (B) — S3 backups, then E-11 on the Operations page
- "The database goes to S3 every hour on its own: 118 of 120 scheduled backups worked. Both misses were
  on test day, and both taught us something."
- "We tested a real restore: emptied the database, restored it from S3, and logged back in — 3 users,
  8 conversations and 61 messages came back. It took 30 seconds. We can lose at most one hour of data."

### 4:30 – 5:40 · The incident (B, or both) — Automation page timeline, then the alarm e-mail
- "We filled the disk with a giant log file. The disk alarm e-mailed us after 4 minutes — two minutes
  before users saw any error. Then MongoDB crashed and every question failed."
- "Root cause: a log folder with no size limit. Restarting would not help — the disk was still full.
  We removed the file and added log rotation; we proved it by writing a 120 MB log and watching it shrink."
- "Testing also found three hidden problems: our outside health check said OK while users had errors; a
  failed backup left an empty file the restore would have used; and later our own update stopped the
  backup with 'Permission denied'. We fixed all three."

### 5:40 – 6:20 · Security and cost (A) — Operations security section, then Results cost
"Each of us signs in with our own AWS login and MFA — no shared logins and no access keys at all. The
server only accepts CloudFront and has no SSH port. The Gemini key only works for Gemini, and the Google
account has no billing, so a leaked key cannot cost money.
The whole system costs 82 US cents a day; all our monitoring, backups and HTTPS add only 0.2 cents.
And when we checked our budget alert, we found it counted the free credits and its e-mails were never
verified — so it could never have warned us. We fixed it."

### 6:20 – 7:00 · Results and next steps (both) — Results page, then Next steps
- "Quality: 30 out of 30 test questions, on day one and again on day five. But here is one it gets
  partly wrong" — show the coffee-shop answer — "it missed the 'no food' rule, and our test did not
  catch it. We list both as next steps."
- "Our trade-off: we chose security and operations over high availability. The first thing we would add
  is a self-healing Auto Scaling group."
- "Thank you."
