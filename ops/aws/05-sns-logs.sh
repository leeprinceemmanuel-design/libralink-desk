#!/usr/bin/env bash
# DAY 1, STEP 5 - alert email topic + log groups with a retention period (WS-B items 3 and 4).
#   ALERT_EMAILS="you@example.com,partner@example.com" bash ops/aws/05-sns-logs.sh
# Each address gets a "AWS Notification - Subscription Confirmation" email: CLICK THE LINK in it,
# or no alarm email will ever arrive.
source "$(dirname "$0")/config.sh"
: "${ALERT_EMAILS:?set ALERT_EMAILS=\"a@x.com,b@y.com\"}"

say "SNS topic $TOPIC_NAME"
TOPIC_ARN=$(aws sns create-topic --name "$TOPIC_NAME" --tags $TAGS_KV --query TopicArn --output text)
save_state TOPIC_ARN "$TOPIC_ARN"
IFS=',' read -ra emails <<<"$ALERT_EMAILS"
for e in "${emails[@]}"; do
  aws sns subscribe --topic-arn "$TOPIC_ARN" --protocol email --notification-endpoint "$(echo "$e" | xargs)" >/dev/null
  echo "  subscription request sent to $e - confirm it from the inbox"
done
aws ssm put-parameter --name "$PARAM_PREFIX/config/SNS_TOPIC_ARN" --type String --value "$TOPIC_ARN" --overwrite >/dev/null

say "Log groups (14-day retention; automation log 30 days)"
for g in $LOG_GROUPS; do
  aws logs create-log-group --log-group-name "$g" --tags "Project=$PROJECT,Team=$TEAM" 2>/dev/null || true
  days=14; [[ "$g" == "/libralink/automation" ]] && days=30
  aws logs put-retention-policy --log-group-name "$g" --retention-in-days "$days"
done
aws logs describe-log-groups --log-group-name-prefix /libralink \
  --query 'logGroups[].[logGroupName,retentionInDays]' --output table
