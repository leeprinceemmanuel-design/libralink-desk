"""AUTOMATION 2 - scheduled health check (EventBridge runs this every 15 minutes).

Runs OUTSIDE the server, so it still notices when the whole instance is down.
Checks, through the public HTTPS address (CloudFront):
  1. /health returns 200 "OK"           -> LibreChat is running
  2. the home page contains libralink.css -> nginx is serving the reskinned site
Publishes LibraLink/HealthCheckOK (1 or 0) and LibraLink/HealthCheckLatencyMs.
The alarm libralink-healthcheck-failed emails the team when HealthCheckOK drops to 0
or when this function stops running at all (missing data counts as failing).
Every run prints one JSON line (with a timestamp) to CloudWatch Logs = proof it ran unattended.
"""
import json
import os
import time
import urllib.error
import urllib.request

import boto3

TARGET = os.environ["TARGET_URL"].rstrip("/")
cloudwatch = boto3.client("cloudwatch")


def fetch(path):
    req = urllib.request.Request(TARGET + path, headers={"User-Agent": "libralink-healthcheck/1.0"})
    start = time.time()
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            body = r.read(20000).decode("utf-8", errors="ignore")
            return r.status, body, int((time.time() - start) * 1000)
    except urllib.error.HTTPError as e:
        return e.code, "", int((time.time() - start) * 1000)
    except Exception as e:  # timeout, DNS, connection refused
        return 0, str(e), int((time.time() - start) * 1000)


def handler(event, context):
    s1, b1, ms1 = fetch("/health")
    s2, b2, ms2 = fetch("/")
    checks = {
        "health_endpoint": s1 == 200 and "OK" in b1,
        "reskinned_home_page": s2 == 200 and "libralink.css" in b2,
    }
    ok = all(checks.values())
    cloudwatch.put_metric_data(Namespace="LibraLink", MetricData=[
        {"MetricName": "HealthCheckOK", "Value": 1 if ok else 0, "Unit": "Count"},
        {"MetricName": "HealthCheckLatencyMs", "Value": ms1 + ms2, "Unit": "Milliseconds"},
    ])
    result = {
        "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "job": "healthcheck", "result": "ok" if ok else "fail",
        "checks": checks, "status": [s1, s2], "latency_ms": ms1 + ms2,
        "trigger": "schedule" if event.get("source") == "aws.events" else "manual",
    }
    print(json.dumps(result))
    return result
