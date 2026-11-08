#!/usr/bin/env bash
# DAY 1, STEP 3 - the S3 bucket (the main AWS integration: the assistant reads its handbook from here).
#   bash ops/aws/03-s3.sh
# - private bucket, all public access blocked, encrypted, VERSIONING ON (WS-C item 3)
# - lifecycle: backups/ deleted after 8 days (keeps 7 full days); old content versions after 30 days
# - uploads the handbook files from content/
# Re-run any time you change the handbook, then restart the app on the server.
source "$(dirname "$0")/config.sh"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

say "Bucket s3://$BUCKET"
if ! aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  aws s3api create-bucket --bucket "$BUCKET" --create-bucket-configuration "LocationConstraint=$AWS_REGION" >/dev/null
fi
aws s3api put-public-access-block --bucket "$BUCKET" --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
aws s3api put-bucket-encryption --bucket "$BUCKET" --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"},"BucketKeyEnabled":true}]}'
aws s3api put-bucket-versioning --bucket "$BUCKET" --versioning-configuration Status=Enabled
aws s3api put-bucket-tagging --bucket "$BUCKET" --tagging "{\"TagSet\":$TAGS_JSON}"
aws s3api put-bucket-lifecycle-configuration --bucket "$BUCKET" --lifecycle-configuration '{
  "Rules": [
    {"ID": "backups-keep-7-days", "Status": "Enabled", "Filter": {"Prefix": "backups/"},
     "Expiration": {"Days": 8}, "NoncurrentVersionExpiration": {"NoncurrentDays": 1}},
    {"ID": "content-old-versions-30-days", "Status": "Enabled", "Filter": {"Prefix": "content/"},
     "NoncurrentVersionExpiration": {"NoncurrentDays": 30}}
  ]}'

say "Uploading the handbook"
aws s3 sync "$ROOT/content/" "s3://$BUCKET/content/" --delete --exclude "*" --include "*.md"
aws s3 ls "s3://$BUCKET/content/"

say "Versioning status (evidence for WS-C):"
aws s3api get-bucket-versioning --bucket "$BUCKET"
