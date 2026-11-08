#!/usr/bin/env bash
# DAY 1, STEP 8 - close the server to the internet; only CloudFront may reach port 80 (WS-D item 5).
#   bash ops/aws/08-lockdown.sh
# Uses AWS's managed list of CloudFront addresses, so we never have to maintain IP ranges.
source "$(dirname "$0")/config.sh"
: "${SG_ID:?run 06-ec2.sh first}"

PL_ID=$(aws ec2 describe-managed-prefix-lists \
          --filters Name=prefix-list-name,Values=com.amazonaws.global.cloudfront.origin-facing \
          --query 'PrefixLists[0].PrefixListId' --output text)

say "Allow port 80 from CloudFront only ($PL_ID)"
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --ip-permissions \
  "IpProtocol=tcp,FromPort=80,ToPort=80,PrefixListIds=[{PrefixListId=$PL_ID,Description=CloudFront-origin-facing-only}]" \
  >/dev/null 2>&1 || echo "(rule already there)"

say "Remove the open-to-the-world rule"
aws ec2 revoke-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 80 --cidr 0.0.0.0/0 \
  >/dev/null 2>&1 || echo "(already removed)"

say "Rules now (evidence for the security before/after table):"
aws ec2 describe-security-groups --group-ids "$SG_ID" \
  --query 'SecurityGroups[0].IpPermissions[].{Port:FromPort,OpenTo:IpRanges[].CidrIp,CloudFrontList:PrefixListIds[].PrefixListId}' \
  --output json
echo
echo "Test: http://$PUBLIC_DNS should now TIME OUT, while https://$CF_DOMAIN still works."
