#!/usr/bin/env bash
# DAY 1, STEP 2 - people and permissions (WS-D items 1 and 2).
# Run ONCE from CloudShell while signed in as the account root user (root must already have MFA).
#   IAM_USERS="lee partner" bash ops/aws/02-iam.sh
#
# Creates:
#   group SAM10-Operators : ReadOnlyAccess + "manage my own password and MFA" + may switch into SAM10-Admin
#   role  SAM10-Admin     : AdministratorAccess, can only be assumed by an operator WITH MFA, max 1 hour
#   one IAM user per person, in that group, with a one-time password (must change at first sign-in)
# No access keys are created. All CLI work is done in CloudShell after switching role.
source "$(dirname "$0")/config.sh"
: "${IAM_USERS:?set IAM_USERS=\"lee partner\"}"
P="$(dirname "$0")/policies"

say "Role SAM10-Admin (MFA required to assume)"
sed "s/__ACCOUNT_ID__/$ACCOUNT_ID/g" "$P/admin-role-trust.json" > /tmp/trust.json
aws iam create-role --role-name SAM10-Admin --assume-role-policy-document file:///tmp/trust.json \
  --max-session-duration 3600 --tags $TAGS_KV >/dev/null 2>&1 || echo "(role exists)"
aws iam attach-role-policy --role-name SAM10-Admin --policy-arn arn:aws:iam::aws:policy/AdministratorAccess

say "Group SAM10-Operators"
aws iam create-group --group-name SAM10-Operators >/dev/null 2>&1 || echo "(group exists)"
aws iam attach-group-policy --group-name SAM10-Operators --policy-arn arn:aws:iam::aws:policy/ReadOnlyAccess
aws iam put-group-policy --group-name SAM10-Operators --policy-name manage-own-credentials \
  --policy-document "file://$P/self-manage-mfa.json"
sed "s/__ACCOUNT_ID__/$ACCOUNT_ID/g" "$P/assume-admin.json" > /tmp/assume.json
aws iam put-group-policy --group-name SAM10-Operators --policy-name may-assume-sam10-admin \
  --policy-document file:///tmp/assume.json

for u in $IAM_USERS; do
  say "User $u"
  aws iam create-user --user-name "$u" --tags $TAGS_KV >/dev/null 2>&1 || echo "(user exists)"
  aws iam add-user-to-group --user-name "$u" --group-name SAM10-Operators
  if ! aws iam get-login-profile --user-name "$u" >/dev/null 2>&1; then
    pw="Ll-$(openssl rand -base64 18 | tr -d '/+=')-9a"
    aws iam create-login-profile --user-name "$u" --password "$pw" --password-reset-required >/dev/null
    echo "  One-time password for $u (give it to them privately, then clear this screen): $pw"
  fi
done

cat <<EOF

Sign-in URL for the IAM users:  https://$ACCOUNT_ID.signin.aws.amazon.com/console
Next, EACH person:
  1. signs in, sets a new password
  2. top-right menu > Security credentials > Assign MFA device (authenticator app)
  3. signs out and in again (so the session has MFA)
  4. top-right menu > Switch role: account $ACCOUNT_ID, role SAM10-Admin
After that, stop using the root user. Screenshot: IAM > Users (with MFA column) = evidence E-12.
EOF
