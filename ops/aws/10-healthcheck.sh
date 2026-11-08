#!/usr/bin/env bash
# DAY 2, STEP 2 - AUTOMATION 2: scheduled health check Lambda (WS-E).
#   bash ops/aws/10-healthcheck.sh
# EventBridge rule runs it every 15 minutes. Logs go to /aws/lambda/libralink-healthcheck.
source "$(dirname "$0")/config.sh"
: "${CF_DOMAIN:?run 07-cloudfront.sh first}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FN=libralink-healthcheck

say "Role for the function (logs + one metric namespace, nothing else)"
cat > /tmp/lambda-trust.json <<'EOF'
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}
EOF
aws iam create-role --role-name libralink-healthcheck-role --assume-role-policy-document file:///tmp/lambda-trust.json \
  --tags $TAGS_KV >/dev/null 2>&1 || echo "(role exists)"
aws iam attach-role-policy --role-name libralink-healthcheck-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
aws iam put-role-policy --role-name libralink-healthcheck-role --policy-name put-libralink-metrics --policy-document '{
  "Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":"cloudwatch:PutMetricData","Resource":"*",
  "Condition":{"StringEquals":{"cloudwatch:namespace":"LibraLink"}}}]}'
ROLE_ARN=$(aws iam get-role --role-name libralink-healthcheck-role --query Role.Arn --output text)
sleep 10

say "Function $FN"
python3 -c "import zipfile,sys; z=zipfile.ZipFile('/tmp/healthcheck.zip','w'); z.write(sys.argv[1], 'healthcheck.py'); z.close()" "$ROOT/ops/lambda/healthcheck.py"
if aws lambda get-function --function-name "$FN" >/dev/null 2>&1; then
  aws lambda update-function-code --function-name "$FN" --zip-file fileb:///tmp/healthcheck.zip >/dev/null
  aws lambda wait function-updated --function-name "$FN"
  aws lambda update-function-configuration --function-name "$FN" \
    --environment "Variables={TARGET_URL=https://$CF_DOMAIN}" >/dev/null
else
  aws lambda create-function --function-name "$FN" --runtime python3.12 --handler healthcheck.handler \
    --role "$ROLE_ARN" --zip-file fileb:///tmp/healthcheck.zip --timeout 30 --memory-size 128 \
    --environment "Variables={TARGET_URL=https://$CF_DOMAIN}" --tags "Project=$PROJECT,Team=$TEAM" >/dev/null
  aws lambda wait function-active --function-name "$FN"
fi
aws logs create-log-group --log-group-name "/aws/lambda/$FN" 2>/dev/null || true
aws logs put-retention-policy --log-group-name "/aws/lambda/$FN" --retention-in-days 30

say "Schedule: every 15 minutes"
RULE_ARN=$(aws events put-rule --name libralink-healthcheck-15min --schedule-expression "rate(15 minutes)" \
             --state ENABLED --description "LibraLink health check" --tags $TAGS_KV --query RuleArn --output text)
aws lambda add-permission --function-name "$FN" --statement-id events-invoke --action lambda:InvokeFunction \
  --principal events.amazonaws.com --source-arn "$RULE_ARN" >/dev/null 2>&1 || true
FN_ARN=$(aws lambda get-function --function-name "$FN" --query Configuration.FunctionArn --output text)
aws events put-targets --rule libralink-healthcheck-15min --targets "Id=1,Arn=$FN_ARN" >/dev/null

say "Test run now (manual - the scheduled runs are the ones that count):"
aws lambda invoke --function-name "$FN" /tmp/hc-out.json >/dev/null && cat /tmp/hc-out.json; echo
