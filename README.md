# LibraLink Desk

A library help-desk AI assistant for the (fictional) Luntian Ridge University Library —
**LibreChat reskinned, deployed to AWS, and operated properly** for the SAM10 Systems
Administration and Maintenance final project.

- **Live system:** https://d2g0ygnhaomokh.cloudfront.net
- **Project website (all documentation, evidence and the video):** https://leeprinceemmanuel-design.github.io/libralink-desk/
- **Team:** Prince Emmanuel C. Lee, John Micheal Agustin

## Credits

Built on **[LibreChat](https://github.com/danny-avila/LibreChat)** by Danny Avila and contributors,
**MIT licence** (<https://github.com/danny-avila/LibreChat/blob/main/LICENSE>). We run the official
Docker image unchanged and reskin it through configuration (`app/`), an nginx layer that adds our
theme and logo, and our own handbook content. The AI model is Google Gemini (free tier, outside AWS).
All university, library and user data in this repository is invented.

## What is where

| Folder | What it holds |
|---|---|
| `app/` | The app stack: `docker-compose.yml`, LibreChat settings (`librechat.env`, `librechat.yaml.tmpl`, `system-prompt.txt`), nginx config, branding (logo, theme CSS) |
| `content/` | Our library handbook (6 Markdown files). Uploaded to S3; the server downloads it at start-up |
| `ops/` | Everything that runs on the server: start/stop, request logger, backup, restore test, CloudWatch agent config, systemd units, fault-injection and fix scripts |
| `ops/aws/` | Numbered scripts run in AWS CloudShell to build the AWS side (budget, IAM, S3, Parameter Store, SNS, EC2, CloudFront, lock-down, monitoring, health check, audit, evidence, teardown) |
| `ops/lambda/` | The health-check Lambda function |
| `eval/` | 30 labelled test questions and the scoring script |
| `docs/` | The project website (GitHub Pages serves this folder) |
| `presentation/` | Script for the 5–8 minute video |
| `GUIDE.md` | The step-by-step build guide we followed |

## How it is deployed (short version)

All AWS commands run in **CloudShell**, signed in with each person's own AWS login (with MFA), so no access keys exist.

```bash
git clone https://github.com/leeprinceemmanuel-design/libralink-desk.git && cd libralink-desk
ALERT_EMAILS="a@example.com,b@example.com" bash ops/aws/01-budget.sh
bash ops/aws/02-iam.sh                                   # checks: no IAM passwords or keys
bash ops/aws/03-s3.sh
bash ops/aws/04-params.sh                                # asks for the Gemini key (hidden)
ALERT_EMAILS="a@example.com,b@example.com" bash ops/aws/05-sns-logs.sh
REPO_URL="https://github.com/leeprinceemmanuel-design/libralink-desk.git" bash ops/aws/06-ec2.sh
bash ops/aws/07-cloudfront.sh
bash ops/aws/08-lockdown.sh
bash ops/aws/09-monitoring.sh
bash ops/aws/10-healthcheck.sh
bash ops/aws/11-audit.sh
```

The server's first-boot script (`ops/bootstrap-ec2.sh`) installs Docker, the CloudWatch agent and
the systemd services, then starts the app. To rebuild a lost server, run `06-ec2.sh` again and restore
the newest backup with `ops/restore-test.sh full`.

## Deploying the automations

1. **Hourly backup** (`ops/backup.sh`) — installed automatically by `ops/bootstrap-ec2.sh` as
   `libralink-backup.timer`. Check it on the server: `systemctl list-timers libralink-backup.timer`.
   To install by hand: copy `ops/systemd/libralink-backup.*` to `/etc/systemd/system/`, then
   `sudo systemctl daemon-reload && sudo systemctl enable --now libralink-backup.timer`.
2. **Health check** (`ops/lambda/healthcheck.py`) — `bash ops/aws/10-healthcheck.sh` in CloudShell
   creates the role, the function and the 15-minute EventBridge schedule. Re-run it after changing the code.

Runs are logged as JSON lines with timestamps in CloudWatch (`/libralink/automation` and
`/aws/lambda/libralink-healthcheck`). `bash ops/aws/12-evidence.sh` prints the latest runs.

## Updating the running system

```bash
# handbook changed:   (CloudShell)
bash ops/aws/03-s3.sh
# code or config changed: (server, Session Manager)
cd /opt/libralink && sudo git pull && sudo bash ops/update-server.sh
# only if files under app/ changed:
sudo systemctl restart libralink
```

## Secrets

No secret is stored in this repository. Settings live in Parameter Store under `/libralink/config/`,
secrets under `/libralink/secret/` (SecureString). `ops/start.sh` reads them into memory when the app
starts. `bash ops/check-secrets.sh` scans the files and the whole git history for keys.

## Contribution log

Who did what, day by day (evidence for the 15% individual mark). Keep this honest and up to date.

| Day / date | Prince Emmanuel C. Lee | John Micheal Agustin |
|---|---|---|
| Day 1 — 8–9 Nov 2026 | Read the brief; ran the original LibreChat locally (E-05); set up the GitHub repo and Pages site; created the AWS account, MFA and budget alert; tested the Free-plan limits and moved the project to Sydney; deployed the server, HTTPS (CloudFront) and lock-down; switched the AI model when Google retired the old one; set up monitoring, alarms, the health check and CloudTrail | Chose the project approach with Lee (Team logins); joined the AWS account through the Team page and set up his own MFA (E-12c); confirmed the alert e-mail subscription; reviewed the plan for Day 2 |
| Day 2 — 9 Nov 2026 | Manual testing (20 + 7 hard questions), found the wrong answer, quality test 30/30, checked restored chats, S3 + alarm-email + CloudWatch evidence during the incident, security evidence script | Server health check, quality test run, restore test (30 s), fault injection, investigation, fix + prevention, fixed the backup permission bug |
| Day 3 — 14 Nov 2026 | Collected final numbers (alarms, health checks, answers, disk/memory, CloudTrail), dashboard + graph + cost screenshots, found and fixed the budget alert (credits + unverified e-mails), checked the Gemini key limits, website, declaration | Checked backups after 5 days (120 OK / 1 failed), re-ran the quality test (30/30), server checks, video (part B) |

Roles: Prince Emmanuel C. Lee — deployment and AWS engineer (server, HTTPS, security, monitoring).
John Micheal Agustin — reliability and testing (quality test, restore test, incident, evidence).
Shared: website, video.

## AI assistance

We used Claude (Anthropic) to help write scripts and draft documentation; see the declaration on the
project website for what it was used for and how we checked it.
