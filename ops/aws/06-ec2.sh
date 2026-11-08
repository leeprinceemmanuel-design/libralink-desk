#!/usr/bin/env bash
# DAY 1, STEP 6 - the server.
#   REPO_URL="https://github.com/<you>/libralink-desk.git" bash ops/aws/06-ec2.sh
#
# - IAM role for the server: Session Manager access + ONLY the permissions in policies/ec2-inline.json
# - security group: port 80 open to everyone for now (this is the BASELINE; 08-lockdown.sh closes it)
# - NO port 22 / SSH: we connect with Session Manager, so there are no SSH keys to lose
# - Amazon Linux 2023, 20 GB encrypted gp3 disk, IMDSv2 required
# - Elastic IP, so the address (and CloudFront's origin) survives a stop/start or resize
# - first-boot script = ops/bootstrap-ec2.sh (installs everything and starts the app)
source "$(dirname "$0")/config.sh"
: "${REPO_URL:?set REPO_URL to your public GitHub repo .git URL}"
REPO_BRANCH="${REPO_BRANCH:-main}"
: "${TOPIC_ARN:?run 05-sns-logs.sh first}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
P="$(dirname "$0")/policies"

say "IAM role for the server (least privilege)"
cat > /tmp/ec2-trust.json <<'EOF'
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}
EOF
aws iam create-role --role-name libralink-ec2-role --assume-role-policy-document file:///tmp/ec2-trust.json \
  --tags $TAGS_KV >/dev/null 2>&1 || echo "(role exists)"
aws iam attach-role-policy --role-name libralink-ec2-role --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
sed -e "s|__REGION__|$AWS_REGION|g" -e "s|__ACCOUNT_ID__|$ACCOUNT_ID|g" -e "s|__BUCKET__|$BUCKET|g" \
    -e "s|__TOPIC_ARN__|$TOPIC_ARN|g" "$P/ec2-inline.json" > /tmp/ec2-inline.json
aws iam put-role-policy --role-name libralink-ec2-role --policy-name libralink-least-privilege \
  --policy-document file:///tmp/ec2-inline.json
aws iam create-instance-profile --instance-profile-name libralink-ec2-profile >/dev/null 2>&1 || true
aws iam add-role-to-instance-profile --instance-profile-name libralink-ec2-profile \
  --role-name libralink-ec2-role 2>/dev/null || true
sleep 10   # IAM needs a few seconds before EC2 can use a new profile

say "Security group (baseline: HTTP open to the world, no SSH)"
VPC_ID=$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text)
SG_ID=$(aws ec2 describe-security-groups --filters Name=group-name,Values=libralink-web-sg Name=vpc-id,Values="$VPC_ID" \
          --query 'SecurityGroups[0].GroupId' --output text)
if [[ "$SG_ID" == "None" ]]; then
  SG_ID=$(aws ec2 create-security-group --group-name libralink-web-sg --vpc-id "$VPC_ID" \
            --description "LibraLink Desk web (HTTP only, no SSH)" \
            --tag-specifications "ResourceType=security-group,Tags=[{Key=Project,Value=$PROJECT},{Key=Team,Value=$TEAM}]" \
            --query GroupId --output text)
  aws ec2 authorize-security-group-ingress --group-id "$SG_ID" \
    --ip-permissions 'IpProtocol=tcp,FromPort=80,ToPort=80,IpRanges=[{CidrIp=0.0.0.0/0,Description="BASELINE - temporary, removed by 08-lockdown"}]' >/dev/null
fi
save_state SG_ID "$SG_ID"

say "Launching $INSTANCE_TYPE"
AMI_ID=$(aws ssm get-parameter --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
           --query Parameter.Value --output text)
sed -e "s|__REPO_URL__|$REPO_URL|" -e "s|__REPO_BRANCH__|$REPO_BRANCH|" "$ROOT/ops/bootstrap-ec2.sh" > /tmp/user-data.sh
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id "$AMI_ID" --instance-type "$INSTANCE_TYPE" \
  --iam-instance-profile Name=libralink-ec2-profile \
  --security-group-ids "$SG_ID" \
  --metadata-options HttpTokens=required,HttpEndpoint=enabled,HttpPutResponseHopLimit=1 \
  --block-device-mappings 'DeviceName=/dev/xvda,Ebs={VolumeSize=20,VolumeType=gp3,Encrypted=true,DeleteOnTermination=true}' \
  --user-data file:///tmp/user-data.sh \
  --tag-specifications \
    "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME},{Key=Project,Value=$PROJECT},{Key=Team,Value=$TEAM}]" \
    "ResourceType=volume,Tags=[{Key=Name,Value=$INSTANCE_NAME-root},{Key=Project,Value=$PROJECT},{Key=Team,Value=$TEAM}]" \
  --query 'Instances[0].InstanceId' --output text)
save_state INSTANCE_ID "$INSTANCE_ID"
echo "  instance $INSTANCE_ID - waiting for it to start..."
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"

say "Elastic IP"
ALLOC_ID=$(aws ec2 allocate-address --domain vpc \
  --tag-specifications "ResourceType=elastic-ip,Tags=[{Key=Name,Value=$INSTANCE_NAME},{Key=Project,Value=$PROJECT},{Key=Team,Value=$TEAM}]" \
  --query AllocationId --output text)
save_state ALLOC_ID "$ALLOC_ID"
aws ec2 associate-address --instance-id "$INSTANCE_ID" --allocation-id "$ALLOC_ID" >/dev/null
sleep 5
PUBLIC_DNS=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
               --query 'Reservations[0].Instances[0].PublicDnsName' --output text)
save_state PUBLIC_DNS "$PUBLIC_DNS"

cat <<EOF

Server: $INSTANCE_ID   address: http://$PUBLIC_DNS
The first-boot script takes about 5-10 minutes (it downloads Docker images).
Check progress: EC2 > Instances > $INSTANCE_NAME > Connect > Session Manager, then run:
    sudo tail -f /var/log/cloud-init-output.log
When it prints "LibraLink bootstrap finished", open http://$PUBLIC_DNS
(BASELINE: plain HTTP, open to everyone. Screenshot this for the Baseline page, then run 07-cloudfront.sh.)
EOF
