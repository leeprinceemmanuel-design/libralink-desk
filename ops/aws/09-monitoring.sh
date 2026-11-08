#!/usr/bin/env bash
# DAY 2, STEP 1 - CloudWatch: custom metrics, alarms and the dashboard (WS-B).
#   bash ops/aws/09-monitoring.sh
#
# Custom metrics (namespace LibraLink) come from METRIC FILTERS on our JSON logs, so the app
# itself did not need changing:
#   /libralink/requests   -> AnswersTotal, AnswersFailed, EmptyAnswer, NotFound, AnswerDurationMs, PIIFlagged
#   /libralink/nginx      -> RequestCount, Nginx5xx
#   /libralink/automation -> BackupSucceeded, BackupBytes
# Every alarm emails the SNS topic. Thresholds are explained in docs/operations.html.
source "$(dirname "$0")/config.sh"
: "${INSTANCE_ID:?run 06-ec2.sh first}" "${TOPIC_ARN:?run 05-sns-logs.sh first}"
NS=LibraLink

filter() {  # log-group  filter-name  pattern  metric  value  [default]
  local t="{\"metricName\":\"$4\",\"metricNamespace\":\"$NS\",\"metricValue\":\"$5\""
  [[ -n "${6:-}" ]] && t="$t,\"defaultValue\":$6"
  aws logs put-metric-filter --log-group-name "$1" --filter-name "$2" \
    --filter-pattern "$3" --metric-transformations "[$t}]"
  echo "  metric $4  <=  $1  $3"
}

say "Metric filters"
filter /libralink/requests answers-total   '{ $.event = "answer" }'                         AnswersTotal 1 0
filter /libralink/requests answers-failed  '{ $.event = "answer" && $.success IS FALSE }'   AnswersFailed 1 0
filter /libralink/requests answers-empty   '{ $.event = "answer" && $.empty IS TRUE }'      EmptyAnswer 1 0
filter /libralink/requests answers-notfound '{ $.event = "answer" && $.not_found IS TRUE }' NotFound 1 0
filter /libralink/requests answer-duration '{ $.event = "answer" && $.duration_ms > 0 }'   AnswerDurationMs '$.duration_ms'
filter /libralink/requests pii-flagged     '{ $.pii_flag IS TRUE }'                         PIIFlagged 1 0
filter /libralink/nginx    requests-all    '{ $.status > 0 }'                               RequestCount 1 0
filter /libralink/nginx    requests-5xx    '{ $.status >= 500 }'                            Nginx5xx 1 0
filter /libralink/automation backup-ok     '{ $.job = "backup" && $.result = "ok" }'        BackupSucceeded 1 0
filter /libralink/automation backup-bytes  '{ $.job = "backup" && $.result = "ok" }'        BackupBytes '$.bytes'

alarm() {  # name description metric namespace stat period evals threshold operator missing [dims]
  local dims=()
  [[ -n "${11:-}" ]] && dims=(--dimensions "${11}")
  aws cloudwatch put-metric-alarm --alarm-name "$1" --alarm-description "$2" \
    --metric-name "$3" --namespace "$4" --statistic "$5" --period "$6" --evaluation-periods "$7" \
    --threshold "$8" --comparison-operator "$9" --treat-missing-data "${10}" "${dims[@]}" \
    --alarm-actions "$TOPIC_ARN" --ok-actions "$TOPIC_ARN" --tags $TAGS_KV
  echo "  alarm $1"
}

say "Alarms (all email $TOPIC_NAME)"
I="Name=InstanceId,Value=$INSTANCE_ID"
alarm libralink-cpu-high "CPU above 85% for 10 minutes: look for a stuck process or a runaway loop." \
  CPUUtilization AWS/EC2 Average 300 2 85 GreaterThanThreshold missing "$I"
alarm libralink-status-check-failed "EC2 status check failed: the instance or its host is unhealthy." \
  StatusCheckFailed AWS/EC2 Maximum 60 2 0 GreaterThanThreshold breaching "$I"
alarm libralink-disk-high "Root disk above 85% for 3 minutes: clean up logs or grow the disk (runbook: disk full)." \
  disk_used_percent CWAgent Average 60 3 85 GreaterThanThreshold missing "$I"
alarm libralink-memory-high "Memory above 90% for 5 minutes: the app may be killed soon." \
  mem_used_percent CWAgent Average 60 5 90 GreaterThanThreshold missing "$I"
alarm libralink-empty-answer "An answer came back EMPTY in the last 30 minutes: model or content problem." \
  EmptyAnswer $NS Sum 1800 1 0 GreaterThanThreshold notBreaching
alarm libralink-slow-answers "Average answer time above 20 s over 15 minutes: the assistant is too slow." \
  AnswerDurationMs $NS Average 900 1 20000 GreaterThanThreshold notBreaching
alarm libralink-nginx-5xx "Server errors (HTTP 5xx) returned to users in the last 5 minutes." \
  Nginx5xx $NS Sum 300 1 0 GreaterThanThreshold notBreaching
alarm libralink-pii-detected "A question looked like it contained personal data (it was redacted in the log)." \
  PIIFlagged $NS Sum 300 1 0 GreaterThanThreshold notBreaching
alarm libralink-backup-missing "No successful backup in the last 2 hours (backups run every hour)." \
  BackupSucceeded $NS Sum 3600 2 1 LessThanThreshold breaching
alarm libralink-healthcheck-failed "Scheduled health check failed or did not run in the last 30 minutes." \
  HealthCheckOK $NS Minimum 1800 1 1 LessThanThreshold breaching

# Rate alarms use metric math: failed answers as a percent of all answers.
rate_alarm() {  # name description numerator-metric threshold-percent period min-answers
  aws cloudwatch put-metric-alarm --alarm-name "$1" --alarm-description "$2" \
    --evaluation-periods 1 --threshold "$4" --comparison-operator GreaterThanThreshold \
    --treat-missing-data notBreaching --alarm-actions "$TOPIC_ARN" --ok-actions "$TOPIC_ARN" --tags $TAGS_KV \
    --metrics "[
      {\"Id\":\"bad\",\"MetricStat\":{\"Metric\":{\"Namespace\":\"$NS\",\"MetricName\":\"$3\"},\"Period\":$5,\"Stat\":\"Sum\"},\"ReturnData\":false},
      {\"Id\":\"all\",\"MetricStat\":{\"Metric\":{\"Namespace\":\"$NS\",\"MetricName\":\"AnswersTotal\"},\"Period\":$5,\"Stat\":\"Sum\"},\"ReturnData\":false},
      {\"Id\":\"pct\",\"Expression\":\"IF(all >= $6, 100*bad/all, 0)\",\"Label\":\"$3 percent\",\"ReturnData\":true}]"
  echo "  alarm $1"
}
rate_alarm libralink-answers-failed-rate "More than 5% of answers failed in 15 minutes: the system is up but not working." \
  AnswersFailed 5 900 1
rate_alarm libralink-notfound-spike "More than half of answers were 'not in the handbook' in 30 minutes: the handbook may be missing." \
  NotFound 50 1800 4

say "Dashboard libralink-ops"
body=$(python3 - "$AWS_REGION" "$INSTANCE_ID" <<'EOF'
import json, sys
region, iid = sys.argv[1], sys.argv[2]
NS = "LibraLink"
def w(x, y, title, metrics, stat="Sum", period=300, wd=8, h=6, extra=None):
    props = {"title": title, "region": region, "metrics": metrics, "stat": stat,
             "period": period, "view": "timeSeries", "stacked": False}
    if extra: props.update(extra)
    return {"type": "metric", "x": x, "y": y, "width": wd, "height": h, "properties": props}
pct = {"yAxis": {"left": {"min": 0, "max": 100}}}
widgets = [
  {"type": "text", "x": 0, "y": 0, "width": 24, "height": 2, "properties": {"markdown":
    "## LibraLink Desk - operations\nThresholds: CPU 85% / 10 min (headroom before slowdown), disk 85% (time to clean up before it is full), memory 90%, answers slower than 20 s average (AI answers stream for several seconds, so 3 s would always fire), failed answers above 5%."}},
  w(0, 2, "Requests (nginx) and answers", [[NS, "RequestCount", {"label": "HTTP requests"}], [NS, "AnswersTotal", {"label": "Answers"}]]),
  w(8, 2, "Errors", [[NS, "Nginx5xx", {"label": "HTTP 5xx"}], [NS, "AnswersFailed", {"label": "Failed answers"}], [NS, "EmptyAnswer", {"label": "Empty answers"}]]),
  w(16, 2, "Answer time (ms)", [[NS, "AnswerDurationMs", {"stat": "Average", "label": "Average"}], [NS, "AnswerDurationMs", {"stat": "Maximum", "label": "Slowest"}]], stat="Average"),
  w(0, 8, "CPU %", [["AWS/EC2", "CPUUtilization", "InstanceId", iid]], stat="Average", extra=pct),
  w(8, 8, "Disk used % (root) and memory %", [["CWAgent", "disk_used_percent", "InstanceId", iid, {"label": "Disk used %"}], ["CWAgent", "mem_used_percent", "InstanceId", iid, {"label": "Memory used %"}]], stat="Average", period=60, extra=pct),
  w(16, 8, "Health check (1 = OK)", [[NS, "HealthCheckOK", {"stat": "Minimum"}], [NS, "HealthCheckLatencyMs", {"stat": "Average", "yAxis": "right"}]], stat="Minimum", period=900),
  w(0, 14, "Database: backup size (bytes)", [[NS, "BackupBytes", {"stat": "Maximum"}]], stat="Maximum", period=3600),
  w(8, 14, "'Not in handbook' answers", [[NS, "NotFound"], [NS, "AnswersTotal", {"label": "All answers"}]], period=900),
  {"type": "alarm", "x": 16, "y": 14, "width": 8, "height": 6, "properties": {"title": "Alarms", "alarms": []}},
]
print(json.dumps({"widgets": widgets}))
EOF
)
# fill the alarm widget with our alarm ARNs
arns=$(aws cloudwatch describe-alarms --alarm-name-prefix libralink- --query 'MetricAlarms[].AlarmArn' --output json)
body=$(python3 -c 'import json,sys; b=json.loads(sys.argv[1]); b["widgets"][-1]["properties"]["alarms"]=json.loads(sys.argv[2]); print(json.dumps(b))' "$body" "$arns")
aws cloudwatch put-dashboard --dashboard-name libralink-ops --dashboard-body "$body" >/dev/null

say "Alarm list (evidence E-07):"
aws cloudwatch describe-alarms --alarm-name-prefix libralink- \
  --query 'MetricAlarms[].[AlarmName,StateValue,Threshold]' --output table
echo "Dashboard: https://$AWS_REGION.console.aws.amazon.com/cloudwatch/home?region=$AWS_REGION#dashboards/dashboard/libralink-ops"
