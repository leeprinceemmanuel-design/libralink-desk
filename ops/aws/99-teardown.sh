#!/usr/bin/env bash
# END OF TERM - delete everything (brief section 6.2: "shut everything down").
#   bash ops/aws/99-teardown.sh
# Run only AFTER your grade is released. Also delete your Gemini API key in Google AI Studio.
source "$(dirname "$0")/config.sh"
read -r -p "This DELETES the LibraLink server, data, backups and monitoring. Type DELETE: " ok
[[ "$ok" == "DELETE" ]] || { echo "Cancelled."; exit 1; }

say "Health check + schedule"
aws events remove-targets --rule libralink-healthcheck-15min --ids 1 2>/dev/null || true
aws events delete-rule --name libralink-healthcheck-15min 2>/dev/null || true
aws lambda delete-function --function-name libralink-healthcheck 2>/dev/null || true

say "Alarms + dashboard"
alarms=$(aws cloudwatch describe-alarms --alarm-name-prefix libralink- --query 'MetricAlarms[].AlarmName' --output text)
[[ -n "$alarms" ]] && aws cloudwatch delete-alarms --alarm-names $alarms
aws cloudwatch delete-dashboards --dashboard-names libralink-ops 2>/dev/null || true

if [[ -n "${CF_ID:-}" ]]; then
  say "CloudFront (disable, wait, delete - this takes a while)"
  etag=$(aws cloudfront get-distribution-config --id "$CF_ID" --query ETag --output text)
  aws cloudfront get-distribution-config --id "$CF_ID" --query DistributionConfig > /tmp/cf.json
  python3 -c 'import json;c=json.load(open("/tmp/cf.json"));c["Enabled"]=False;json.dump(c,open("/tmp/cf.json","w"))'
  aws cloudfront update-distribution --id "$CF_ID" --if-match "$etag" --distribution-config file:///tmp/cf.json >/dev/null
  aws cloudfront wait distribution-deployed --id "$CF_ID"
  etag=$(aws cloudfront get-distribution --id "$CF_ID" --query ETag --output text)
  aws cloudfront delete-distribution --id "$CF_ID" --if-match "$etag"
fi

say "Server, Elastic IP, security group"
[[ -n "${INSTANCE_ID:-}" ]] && aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" >/dev/null \
  && aws ec2 wait instance-terminated --instance-ids "$INSTANCE_ID"
[[ -n "${ALLOC_ID:-}" ]] && aws ec2 release-address --allocation-id "$ALLOC_ID" || true
[[ -n "${SG_ID:-}" ]] && aws ec2 delete-security-group --group-id "$SG_ID" || true

say "Buckets (all versions), parameters, logs, topic, trail"
for b in "$BUCKET" "$TRAIL_BUCKET"; do
  aws s3api head-bucket --bucket "$b" 2>/dev/null || continue
  python3 - "$b" <<'EOF'
import json, subprocess, sys
b = sys.argv[1]
while True:
    out = json.loads(subprocess.check_output(["aws", "s3api", "list-object-versions", "--bucket", b, "--max-items", "900", "--output", "json"]) or b"{}")
    objs = [{"Key": o["Key"], "VersionId": o["VersionId"]} for o in out.get("Versions", []) + out.get("DeleteMarkers", [])]
    if not objs: break
    subprocess.check_call(["aws", "s3api", "delete-objects", "--bucket", b, "--delete", json.dumps({"Objects": objs, "Quiet": True})])
EOF
  aws s3api delete-bucket --bucket "$b"
done
names=$(aws ssm describe-parameters --parameter-filters "Key=Name,Option=BeginsWith,Values=$PARAM_PREFIX/" --query 'Parameters[].Name' --output text)
[[ -n "$names" ]] && aws ssm delete-parameters --names $names >/dev/null
for g in $LOG_GROUPS /aws/lambda/libralink-healthcheck; do aws logs delete-log-group --log-group-name "$g" 2>/dev/null || true; done
[[ -n "${TOPIC_ARN:-}" ]] && aws sns delete-topic --topic-arn "$TOPIC_ARN" || true
aws cloudtrail delete-trail --name libralink-trail 2>/dev/null || true

echo
say "Server and health-check roles"
aws iam remove-role-from-instance-profile --instance-profile-name libralink-ec2-profile --role-name libralink-ec2-role 2>/dev/null || true
aws iam delete-instance-profile --instance-profile-name libralink-ec2-profile 2>/dev/null || true
aws iam detach-role-policy --role-name libralink-ec2-role --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore 2>/dev/null || true
aws iam delete-role-policy --role-name libralink-ec2-role --policy-name libralink-least-privilege 2>/dev/null || true
aws iam delete-role --role-name libralink-ec2-role 2>/dev/null || true
aws iam detach-role-policy --role-name libralink-healthcheck-role --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true
aws iam delete-role-policy --role-name libralink-healthcheck-role --policy-name put-libralink-metrics 2>/dev/null || true
aws iam delete-role --role-name libralink-healthcheck-role 2>/dev/null || true
echo "Left on purpose: the budget and your partner on the Team page."
echo "Then tell your instructor everything is shut down (brief section 6.2)."
