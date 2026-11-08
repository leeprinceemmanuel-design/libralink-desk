#!/usr/bin/env bash
# DAY 1, STEP 7 - HTTPS with CloudFront (WS-A item 3). Free certificate on *.cloudfront.net.
#   bash ops/aws/07-cloudfront.sh
# - viewers: HTTPS only (HTTP is redirected)
# - origin: our EC2 server on port 80 (only CloudFront will be allowed in, after 08-lockdown.sh)
# - caching OFF (every chat is unique), all headers/cookies passed through
source "$(dirname "$0")/config.sh"
: "${PUBLIC_DNS:?run 06-ec2.sh first}"

cfg=$(python3 - "$PUBLIC_DNS" <<'EOF'
import json, sys, time
dns = sys.argv[1]
methods = ["GET","HEAD","OPTIONS","PUT","POST","PATCH","DELETE"]
print(json.dumps({
  "DistributionConfig": {
    "CallerReference": f"libralink-{int(time.time())}",
    "Comment": "LibraLink Desk (SAM10)",
    "Enabled": True,
    "PriceClass": "PriceClass_200",
    "HttpVersion": "http2",
    "Origins": {"Quantity": 1, "Items": [{
      "Id": "libralink-ec2", "DomainName": dns,
      "CustomOriginConfig": {"HTTPPort": 80, "HTTPSPort": 443, "OriginProtocolPolicy": "http-only",
                             "OriginReadTimeout": 60, "OriginKeepaliveTimeout": 5,
                             "OriginSslProtocols": {"Quantity": 1, "Items": ["TLSv1.2"]}}}]},
    "DefaultCacheBehavior": {
      "TargetOriginId": "libralink-ec2",
      "ViewerProtocolPolicy": "redirect-to-https",
      "AllowedMethods": {"Quantity": 7, "Items": methods,
                         "CachedMethods": {"Quantity": 2, "Items": ["GET","HEAD"]}},
      "CachePolicyId": "4135ea2d-6df8-44a3-9df3-4b5a84be39ad",          # AWS managed: CachingDisabled
      "OriginRequestPolicyId": "216adef6-5c7f-47e4-b989-5492eafa07d3",  # AWS managed: AllViewer
      "Compress": False
    }
  },
  "Tags": {"Items": [{"Key": "Project", "Value": "SAM10"}, {"Key": "Team", "Value": "libralink"}]}
}))
EOF
)

say "Creating the CloudFront distribution"
out=$(aws cloudfront create-distribution-with-tags --distribution-config-with-tags "$cfg" \
        --query 'Distribution.[Id,DomainName]' --output text)
CF_ID=$(echo "$out" | awk '{print $1}'); CF_DOMAIN=$(echo "$out" | awk '{print $2}')
save_state CF_ID "$CF_ID"; save_state CF_DOMAIN "$CF_DOMAIN"
aws ssm put-parameter --name "$PARAM_PREFIX/config/PUBLIC_URL" --type String \
  --value "https://$CF_DOMAIN" --overwrite >/dev/null

cat <<EOF

CloudFront: $CF_ID  ->  https://$CF_DOMAIN
It takes 5-15 minutes to deploy (status "Deploying" -> "Enabled" in the CloudFront console).

Then on the server (Session Manager), restart the app so it knows its new HTTPS address:
    sudo systemctl restart libralink
and open https://$CF_DOMAIN  (padlock = HTTPS works). Then run 08-lockdown.sh.
EOF
