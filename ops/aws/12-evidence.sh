#!/usr/bin/env bash
# Prints command output that makes good, un-editable evidence (brief appendix G.2).
#   bash ops/aws/12-evidence.sh | tee evidence-$(date +%F).txt
# Before you paste any of this on the website: it contains NO secret values (only names),
# but still read it once.
source "$(dirname "$0")/config.sh"

say "Who am I (aws sts get-caller-identity)"
aws sts get-caller-identity --query '{Account:Account,Arn:Arn}'

say "E-02 / E-18  Server (aws ec2 describe-instances)"
aws ec2 describe-instances --filters "Name=tag:Project,Values=$PROJECT" \
  --query 'Reservations[].Instances[].{Id:InstanceId,Type:InstanceType,State:State.Name,IMDSv2:MetadataOptions.HttpTokens,PublicDNS:PublicDnsName,Tags:Tags[?Key==`Name`]|[0].Value}' \
  --output table

say "E-10  Backups in S3 (newest 5) + versioning + lifecycle"
aws s3api list-objects-v2 --bucket "$BUCKET" --prefix backups/mongo/ \
  --query 'reverse(sort_by(Contents,&LastModified))[:5].[Key,Size,LastModified]' --output table
aws s3api get-bucket-versioning --bucket "$BUCKET"
aws s3api get-bucket-lifecycle-configuration --bucket "$BUCKET" --query 'Rules[].{Id:ID,Prefix:Filter.Prefix,ExpireDays:Expiration.Days}' --output table

say "E-12  People: no IAM users with passwords, no access keys anywhere"
users=$(aws iam list-users --query 'Users[].UserName' --output text)
[[ -z "$users" ]] && echo "  no IAM users (people sign in with their own AWS logins + MFA via the Team page)"
for u in $users; do
  pw=$(aws iam get-login-profile --user-name "$u" >/dev/null 2>&1 && echo yes || echo no)
  keys=$(aws iam list-access-keys --user-name "$u" --query 'length(AccessKeyMetadata)')
  printf '  %-20s console password: %-3s  access keys: %s\n' "$u" "$pw" "$keys"
done
echo "Roles we created (machines only):"
aws iam list-roles --query 'Roles[?starts_with(RoleName,`libralink-`)].RoleName' --output text | tr '\t' '\n' | sed 's/^/  /'

say "E-13  Parameter Store (names and types only)"
aws ssm describe-parameters --parameter-filters "Key=Name,Option=BeginsWith,Values=$PARAM_PREFIX/" \
  --query 'Parameters[].[Name,Type]' --output table

say "E-14  Automations - last runs"
echo "Backups (from /libralink/automation):"
aws logs filter-log-events --log-group-name /libralink/automation --filter-pattern '{ $.job = "backup" }' \
  --query 'events[-6:].message' --output text | tr '\t' '\n'
echo "Health checks (scheduled runs only):"
aws logs filter-log-events --log-group-name /aws/lambda/libralink-healthcheck --filter-pattern '"schedule"' \
  --query 'events[-6:].message' --output text | tr '\t' '\n'

say "E-07  Alarms"
aws cloudwatch describe-alarms --alarm-name-prefix libralink- --query 'MetricAlarms[].[AlarmName,StateValue]' --output table

say "Alarm history (state changes) - use this for time to detect"
aws cloudwatch describe-alarm-history --history-item-type StateUpdate --max-records 30 \
  --query 'AlarmHistoryItems[?starts_with(AlarmName,`libralink-`)].[Timestamp,AlarmName,HistorySummary]' --output table

say "E-09  Sample of the request log (last 5 answers)"
aws logs filter-log-events --log-group-name /libralink/requests --filter-pattern '{ $.event = "answer" }' \
  --query 'events[-5:].message' --output text | tr '\t' '\n'
