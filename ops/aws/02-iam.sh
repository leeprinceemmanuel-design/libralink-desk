#!/usr/bin/env bash
# DAY 1, STEP 2 - people and permissions (WS-D items 1 and 2), FREE-PLAN VERSION.
#   bash ops/aws/02-iam.sh
#
# Why this is different from a "normal" AWS account:
#   Our account is on the AWS Free plan. AWS puts free-plan accounts under its own
#   service control policies (rules set ABOVE our account). We tested them on 9 Nov 2026:
#     - IAM roles, role policies, instance profiles .......... allowed
#     - IAM users with a console password (create-login-profile) .. BLOCKED
#     - IAM groups (attach-group-policy) ....................... BLOCKED
#   So people cannot get classic IAM console users. Instead:
#     - each person signs in with their OWN AWS login (AWS Builder ID), with their OWN MFA,
#       and is added to the account through the console's "Team" page;
#     - nobody shares a login; there are no IAM users with passwords and NO access keys;
#     - machines (the EC2 server, the Lambda health check) get IAM ROLES with only the
#       permissions they need (created by 06-ec2.sh and 10-healthcheck.sh).
#
# This script only (1) removes the leftovers of our first attempt and (2) checks that
# no IAM user has a password or access key.
source "$(dirname "$0")/config.sh"

say "Removing leftovers from the first attempt (SAM10-Admin role, SAM10-Operators group)"
for p in $(aws iam list-attached-role-policies --role-name SAM10-Admin --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null); do
  aws iam detach-role-policy --role-name SAM10-Admin --policy-arn "$p"
done
aws iam delete-role --role-name SAM10-Admin 2>/dev/null && echo "  removed role SAM10-Admin" || echo "  (no SAM10-Admin role)"
for n in $(aws iam list-group-policies --group-name SAM10-Operators --query 'PolicyNames' --output text 2>/dev/null); do
  aws iam delete-group-policy --group-name SAM10-Operators --policy-name "$n" 2>/dev/null || true
done
aws iam delete-group --group-name SAM10-Operators 2>/dev/null && echo "  removed group SAM10-Operators" || echo "  (no SAM10-Operators group, or not allowed)"

say "Check: IAM users, passwords and access keys (should be none)"
users=$(aws iam list-users --query 'Users[].UserName' --output text)
if [[ -z "$users" ]]; then
  echo "  no IAM users - people sign in with their own AWS logins (Team page) with MFA"
else
  for u in $users; do
    pw=$(aws iam get-login-profile --user-name "$u" >/dev/null 2>&1 && echo yes || echo no)
    keys=$(aws iam list-access-keys --user-name "$u" --query 'length(AccessKeyMetadata)')
    printf '  %-20s console password: %-3s  access keys: %s\n' "$u" "$pw" "$keys"
  done
fi

say "Who is running this"
aws sts get-caller-identity --query Arn --output text

cat <<'EOF'

Next (in the console, not here):
  1. Menu "<account name>" > Team > invite your partner by e-mail.
  2. Your partner signs in with their own AWS login and registers their own MFA device.
  3. Screenshot the Team page (both members) = evidence E-12; your own MFA page = E-12b.
EOF
