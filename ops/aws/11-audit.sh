#!/usr/bin/env bash
# DAY 2, STEP 3 - audit trail and threat detection (WS-D items 6 and 8).
#   bash ops/aws/11-audit.sh
# - CloudTrail trail "libralink-trail" writing to its own private bucket (who did what)
# - GuardDuty: BLOCKED on our Free-plan account (explicit deny in a service control policy, 9 Nov 2026).
#   The script tries it and carries on if it is not allowed.
source "$(dirname "$0")/config.sh"

say "CloudTrail bucket s3://$TRAIL_BUCKET"
if ! aws s3api head-bucket --bucket "$TRAIL_BUCKET" 2>/dev/null; then
  aws s3api create-bucket --bucket "$TRAIL_BUCKET" --create-bucket-configuration "LocationConstraint=$AWS_REGION" >/dev/null
fi
aws s3api put-public-access-block --bucket "$TRAIL_BUCKET" --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
aws s3api put-bucket-tagging --bucket "$TRAIL_BUCKET" --tagging "{\"TagSet\":$TAGS_JSON}"
aws s3api put-bucket-lifecycle-configuration --bucket "$TRAIL_BUCKET" --lifecycle-configuration \
  '{"Rules":[{"ID":"expire-90-days","Status":"Enabled","Filter":{"Prefix":""},"Expiration":{"Days":90}}]}'
aws s3api put-bucket-policy --bucket "$TRAIL_BUCKET" --policy "{
  \"Version\":\"2012-10-17\",\"Statement\":[
   {\"Sid\":\"AclCheck\",\"Effect\":\"Allow\",\"Principal\":{\"Service\":\"cloudtrail.amazonaws.com\"},
    \"Action\":\"s3:GetBucketAcl\",\"Resource\":\"arn:aws:s3:::$TRAIL_BUCKET\"},
   {\"Sid\":\"Write\",\"Effect\":\"Allow\",\"Principal\":{\"Service\":\"cloudtrail.amazonaws.com\"},
    \"Action\":\"s3:PutObject\",\"Resource\":\"arn:aws:s3:::$TRAIL_BUCKET/AWSLogs/$ACCOUNT_ID/*\",
    \"Condition\":{\"StringEquals\":{\"s3:x-amz-acl\":\"bucket-owner-full-control\"}}}]}"

say "Trail libralink-trail"
aws cloudtrail create-trail --name libralink-trail --s3-bucket-name "$TRAIL_BUCKET" \
  --enable-log-file-validation --tags-list $TAGS_KV >/dev/null 2>&1 || echo "(trail exists)"
aws cloudtrail start-logging --name libralink-trail
aws cloudtrail get-trail-status --name libralink-trail --query '{Logging:IsLogging,LatestDelivery:LatestDeliveryTime}'

say "GuardDuty"
if DET=$(aws guardduty list-detectors --query 'DetectorIds[0]' --output text 2>/dev/null); then
  [[ "$DET" == "None" ]] && DET=$(aws guardduty create-detector --enable --tags "Project=$PROJECT,Team=$TEAM" --query DetectorId --output text)
  echo "  detector $DET enabled"
else
  echo "  GuardDuty is not allowed on this account's plan (service control policy) - skipped"
fi
