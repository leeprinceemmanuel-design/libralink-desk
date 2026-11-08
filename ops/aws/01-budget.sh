#!/usr/bin/env bash
# DAY 1, STEP 1 - cost guard rails (brief: "Set an AWS Budgets alert on day one").
#   ALERT_EMAILS="you@example.com,partner@example.com" BUDGET_USD=10 bash ops/aws/01-budget.sh
# - monthly cost budget with emails at 50%, 80%, 100% (actual) and 100% (forecast)
# - EBS encryption on by default in this region (encryption at rest for every new disk)
source "$(dirname "$0")/config.sh"
: "${ALERT_EMAILS:?set ALERT_EMAILS=\"a@x.com,b@y.com\"}"
BUDGET_USD="${BUDGET_USD:-10}"

subs=$(python3 -c '
import json, sys
print(json.dumps([{"SubscriptionType": "EMAIL", "Address": a.strip()} for a in sys.argv[1].split(",") if a.strip()]))
' "$ALERT_EMAILS")

notifs=$(python3 -c '
import json, sys
subs = json.loads(sys.argv[1])
out = [{"Notification": {"NotificationType": t, "ComparisonOperator": "GREATER_THAN",
         "Threshold": th, "ThresholdType": "PERCENTAGE"}, "Subscribers": subs}
       for t, th in [("ACTUAL", 50), ("ACTUAL", 80), ("ACTUAL", 100), ("FORECASTED", 100)]]
print(json.dumps(out))
' "$subs")

say "Creating budget libralink-monthly (USD $BUDGET_USD)"
aws budgets create-budget --account-id "$ACCOUNT_ID" \
  --budget "{\"BudgetName\":\"libralink-monthly\",\"BudgetLimit\":{\"Amount\":\"$BUDGET_USD\",\"Unit\":\"USD\"},\"TimeUnit\":\"MONTHLY\",\"BudgetType\":\"COST\"}" \
  --notifications-with-subscribers "$notifs" \
  && echo "Budget created." || echo "(Budget may already exist - check Billing > Budgets.)"

say "Turning on EBS encryption by default in $AWS_REGION"
aws ec2 enable-ebs-encryption-by-default --query EbsEncryptionByDefault

say "Done. Screenshot: Billing > Budgets > libralink-monthly (evidence for cost / E-16)."
