# LibraLink Desk — 3-day build guide

Follow the steps **in order**. Each step says what to do, what you should see, and which
screenshot to take (E-xx = the brief's evidence ID; save it in `docs/evidence/` with that exact
file name and the website shows it automatically).

Words used here:
- **CloudShell** — a terminal inside the AWS console (the `>_` icon at the top). No install needed.
- **Session Manager** — a terminal on the EC2 server, opened from the console. Replaces SSH.
- **Parameter Store** — AWS's safe storage for settings and secrets.

> If any command prints an error, stop, copy the whole error, and ask Claude. Do not guess.

---

## Day 1 — accounts, deploy, start the clocks

The automations must run **at least twice on their own**, so the goal of Day 1 is a deployed
system with backups and the health check running by tonight.

### Step 1 — Get a Gemini API key (free)
1. Go to <https://aistudio.google.com>, sign in, click **Get API key** → **Create API key** (in a new project).
2. Copy the key into a password manager or a private note. **Never paste it into code, chat, a screenshot or GitHub.**

### Step 2 — Put the project on GitHub
1. Create a **public** repository named `libralink-desk` (public is needed for free GitHub Pages and so the server can download it — it contains no secrets).
2. Add your partner as a collaborator (Settings → Collaborators).
3. On your laptop (Git Bash on Windows), unzip the project and push it **in a few commits, one per part**, so the history is real:
   ```bash
   cd libralink-desk
   git init -b main
   git config user.name "Your Name"; git config user.email "your-github-email"
   git add content app eval .gitignore && git commit -m "Reskin: LibraLink branding, handbook, prompt, eval questions"
   git add ops && git commit -m "Ops: deploy, monitoring, backup, automation and fault scripts"
   git add docs presentation README.md GUIDE.md && git commit -m "Project website, guide and presentation script"
   git remote add origin https://github.com/<your-user>/libralink-desk.git
   git push -u origin main
   ```
4. Turn on the website: repo **Settings → Pages → Build from a branch → main → /docs → Save**. After a minute it is live at `https://<your-user>.github.io/libralink-desk/`.
5. Your partner should make their own commits from their own account as they fill in their parts (Day 2–3).

### Step 3 — Run the ORIGINAL LibreChat locally (WS-A item 1, evidence E-05)
Needs Docker Desktop running.
```bash
git clone --depth 1 https://github.com/danny-avila/LibreChat.git && cd LibreChat
cp .env.example .env
docker compose up -d
```
Open <http://localhost:3080>, register a test account (invented e-mail, e.g. `test@example.com`).
- 📷 **E-05** → `docs/evidence/E-05-original-librechat.png` (the stock look: LibreChat name, logo, green buttons).
- Write down the version shown in the app or in `docker compose images`.

Then stop it (its container names clash with ours): `docker compose down`, `cd ..`.

*(Optional: run OUR version locally too: `bash ops/local/up.sh`, open <http://localhost:8080>, create a user with `docker exec -it LibreChat npm run create-user`. Stop with `bash ops/local/down.sh`.)*

### Step 4 — Make the AWS account safe (account owner, once)
Our account is on the AWS **Free plan**. It signs the owner in through an AWS-made role and
**blocks IAM console users and groups**, so people are added through the **Team** page instead.
1. Owner login MFA: menu (account name, top right) → **Profile** → **Manage profile** → **Security** →
   **Register device** (authenticator app). 📷 **E-12b** → `E-12b-owner-mfa.png` (MFA box only).
2. Make sure the console address says `region=ap-southeast-1` (Singapore).
3. Open **CloudShell** (bottom-left) and get the code:
   ```bash
   git clone https://github.com/<your-user>/libralink-desk.git && cd libralink-desk
   ```
4. Budget alert first (brief: day one):
   ```bash
   ALERT_EMAILS="you@...,partner@..." BUDGET_USD=10 bash ops/aws/01-budget.sh
   ```
   "Budget created." The encryption-by-default line is blocked on the Free plan; that's expected.
5. Check people and permissions: `bash ops/aws/02-iam.sh` (it removes test leftovers and shows no IAM passwords or keys).
6. Menu → **Team** → invite your partner by e-mail. They accept, sign in with **their own** AWS login, and register **their own** MFA.
   📷 **E-12** → `E-12-team.png` (Team page with both of you).

### Step 5 — Build the AWS side (in CloudShell)
If CloudShell was restarted, `cd libralink-desk && git pull` first.
```bash
bash ops/aws/03-s3.sh
SITE_URL="https://<your-user>.github.io/libralink-desk" bash ops/aws/04-params.sh
```
`04` asks for the Gemini key — paste it and press Enter (nothing shows; that is on purpose).
- 📷 **E-13** → `E-13-parameter-store.png`: Systems Manager → Parameter Store list (names only, **never click Show**).

```bash
ALERT_EMAILS="you@...,partner@..." bash ops/aws/05-sns-logs.sh
```
**Both of you: open the "AWS Notification - Subscription Confirmation" e-mail and click Confirm.**

### Step 6 — Launch the server
```bash
REPO_URL="https://github.com/<your-user>/libralink-desk.git" bash ops/aws/06-ec2.sh
```
Wait 5–10 minutes. Then EC2 → Instances → `libralink-server` → **Connect** → **Session Manager** → Connect:
```bash
sudo tail -n 30 /var/log/cloud-init-output.log     # wait for "LibraLink bootstrap finished"
sudo docker ps                                       # 3 containers: LibreChat, chat-mongodb, libralink-nginx
curl -s localhost/health                             # prints OK
```
Open the `http://ec2-…amazonaws.com` address that `06` printed.
- 📷 **B-01** → `B-01-http-not-secure.png` (browser says "Not secure").
- 📷 **B-02** → `B-02-sg-open.png` (EC2 → Security groups → libralink-web-sg → Inbound: 80 from 0.0.0.0/0).
- 📷 **B-03** → `B-03-baseline-metrics.png` (CloudWatch → Alarms: none yet).
- Write the date/time on the Baseline page. Fill **Well-Architected Pass 1** date now.

Check the model name works and record versions (in Session Manager):
```bash
sudo python3 /opt/libralink/eval/eval.py --list-models | grep -i flash
sudo docker exec LibreChat node -p "require('/app/package.json').version"
```
If `gemini-2.5-flash` is not listed, pick a listed flash model and in CloudShell run
`aws ssm put-parameter --name /libralink/config/GOOGLE_MODEL --type String --overwrite --value <model>`,
then on the server `sudo systemctl restart libralink`.

### Step 7 — HTTPS and lock-down (CloudShell)
```bash
bash ops/aws/07-cloudfront.sh
```
Wait until CloudFront shows **Enabled** (5–15 min). On the server: `sudo systemctl restart libralink`.
Open `https://xxxx.cloudfront.net` — padlock shown.
```bash
bash ops/aws/08-lockdown.sh
```
Now `http://ec2-…` should **time out** and the CloudFront address should still work.

### Step 8 — Create the app accounts (server)
```bash
sudo docker exec -it LibreChat npm run create-user
```
Use **invented** e-mails (e.g. `lee@libralink.example`, `partner@libralink.example`, `demo@libralink.example` for your instructor). Log in on the HTTPS site, accept the terms pop-up, ask: "How many books can an undergraduate borrow?"
- 📷 **E-01** → `E-01-libralink-desk.png` (logo, colours, question and answer).

> If the colours did NOT change, or something still says LibreChat, take a screenshot and ask Claude — LibreChat may have renamed a colour variable.

### Step 9 — Monitoring, health check and audit (CloudShell)
```bash
bash ops/aws/09-monitoring.sh
bash ops/aws/10-healthcheck.sh       # last line should show "result": "ok"
bash ops/aws/11-audit.sh
```
The hourly backup started by itself when the server booted. Check on the server:
`systemctl list-timers 'libralink-*'`. Both automations now run without you. ✅ End of Day 1.

Commit your Day 1 notes (contribution log in README, dates on the website) and push.

---

## Day 2 — prove it works, break it, fix it

### Step 10 — Use it like real users (makes the dashboard real)
Both of you ask 15–20 varied questions over the morning, including some it cannot answer and one in Filipino.
Ask the three test questions from the Results page and copy the real answers into `docs/results.html`.
- 📷 **E-03** → `E-03-test-questions.png`.
- 📷 **E-09** → `E-09-request-log.png` (CloudWatch → Log groups → `/libralink/requests`).

### Step 11 — The quality number (server)
```bash
sudo python3 /opt/libralink/eval/eval.py
```
Takes ~5 minutes. Copy the RESULT line and the per-category scores into Results and the system card.
Open the CSV it names, find a FAIL, and use it as the "example it gets wrong".
- 📷 **E-04** → `E-04-eval-result.png`.

### Step 12 — Restore test (server) — budget 30 minutes
```bash
sudo /opt/libralink/ops/restore-test.sh side     # safe practice run first
sudo /opt/libralink/ops/restore-test.sh full     # the real one
```
Then log in on the website: your old conversations must be in the sidebar.
- 📷 **E-11** → `E-11-restore.png` (terminal output + the app with old chats).
- Write the total seconds as your RTO on the Operations page.
- 📷 **E-10** → `E-10-backups-s3.png` (S3 → backups/mongo/ list + versioning Enabled).

### Step 13 — The incident (server) — budget 45 minutes
```bash
sudo /opt/libralink/ops/fault/fill-disk.sh        # type FILL
```
Ask the assistant a question (it should fail). Wait for the **ALARM: libralink-disk-high** e-mail.
```bash
sudo /opt/libralink/ops/fault/timeline.sh "noticed: disk alarm email received"
df -h /
sudo du -ah /var/log | sort -rh | head
sudo docker logs chat-mongodb --tail 20
sudo docker logs LibreChat --tail 20
ls /etc/logrotate.d/
```
- 📷 **E-08** → `E-08-alert-email.png` (the alarm e-mail, date/time visible).
- 📷 **E-15** → `E-15-investigation.png` (the commands above).
```bash
sudo /opt/libralink/ops/fault/apply-fix.sh
sudo /opt/libralink/ops/fault/verify-fix.sh
cat /var/log/libralink/incident-timeline.txt
```
- 📷 **E-15b** → `E-15b-prevention.png`.
- Fill the timeline, time to detect, time to fix and the runbook dates on the Automation page.

### Step 14 — Security evidence
```bash
bash ops/aws/12-evidence.sh            # CloudShell
```
- 📷 **E-12** → `E-12-team.png` if not taken yet (Team page, both members).
- On your laptop: `bash ops/check-secrets.sh` → 📷 **E-13b** → `E-13b-secret-scan.png`.
- GuardDuty console → Findings: write "none" or explain each on the Operations page.

### Step 15 — (Optional, good for marks) right-size
Look at the dashboard's memory line over the day. If the average is under ~45% on t3.medium, try t3.small
(CloudShell):
```bash
source ops/aws/.state      # loads INSTANCE_ID saved by 06-ec2.sh
aws ec2 stop-instances --instance-ids $INSTANCE_ID && aws ec2 wait instance-stopped --instance-ids $INSTANCE_ID
aws ec2 modify-instance-attribute --instance-id $INSTANCE_ID --instance-type '{"Value":"t3.small"}'
aws ec2 start-instances --instance-ids $INSTANCE_ID
```
The Elastic IP keeps the address, so CloudFront keeps working. Some alarms will fire while it is stopped — that is expected; note it.
Compare equal periods (e.g. 6 hours before vs 6 hours after) for memory, answer time and cost on the Results page.

---

## Day 3 — write it up, record, submit

### Step 16 — Fill the website
```bash
bash ops/check-site.sh
```
It lists every yellow FILL marker and every missing screenshot. Work through them until it says READY.
Rules: only real numbers from your own account; put the date range next to every number; blur e-mail
addresses if you want; **no keys or passwords in any screenshot**.
- 📷 **E-06** → `E-06-dashboard.png`, **E-07** → `E-07-alarms.png`, **E-14** → `E-14-automation-runs.png`,
  **E-16** → `E-16-cost.png`, **R-01** → `R-01-graph.png`.
- Well-Architected Pass 2 date and the FILL numbers.
- Fill the README contribution log honestly — who did what each day.

### Step 17 — Record the video (5–8 minutes)
Use `presentation/script.md`. Show the live system, not slides only. Upload to YouTube as **Unlisted**,
put the video id in `docs/index.html` (replace `VIDEO_ID`). Check nothing secret is visible.

### Step 18 — Final checks and submit
```bash
bash ops/check-secrets.sh
bash ops/check-site.sh
git add -A && git commit -m "Final evidence and results" && git push
```
Make the repository ZIP **with the .git folder** (zip the whole folder on your laptop).
Submit: website URL + repository ZIP (the video is embedded on the site). Both sign the declaration on the website's last page.

### After grading
`bash ops/aws/99-teardown.sh`, remove your partner from the Team page, delete the Gemini key, tell your instructor.

---

## If something goes wrong

| What you see | Most likely cause | What to do |
|---|---|---|
| `LibreChat` container keeps restarting | A setting in `librechat.yaml` this LibreChat version does not accept | `sudo docker logs LibreChat --tail 50` and send the error to Claude |
| CloudFront shows 502 / 504 | Server not reachable or app down | On the server: `curl -s localhost/health`; check the security group still has the CloudFront rule |
| Login works on HTTP but not HTTPS / login loop | App still has the old address | `sudo systemctl restart libralink` (it re-reads PUBLIC_URL) |
| Every answer is an error | Wrong or blocked Gemini key, wrong model name, or free quota used up | `sudo docker logs LibreChat --tail 50`; check the model with `eval.py --list-models` |
| No alarm e-mails | Subscription not confirmed | SNS → Topics → libralink-alerts → Subscriptions must say "Confirmed" |
| `docker compose` pull fails for the LibreChat image | Image name changed | Set `/libralink/config/LIBRECHAT_IMAGE` to `registry.librechat.ai/danny-avila/librechat:latest` and restart |
| Session Manager "Connect" is greyed out | Agent not registered yet, or the server is out of disk | Wait 2 minutes; reboot the instance from the console if needed |
