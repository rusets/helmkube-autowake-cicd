#!/usr/bin/env bash
set -euo pipefail
REGION="${REGION:-us-east-1}"
ASSOC_ID=$(aws ssm list-associations --association-filter-list key=AssociationName,value=helmkube-autowake-helm-deploy-assoc --query 'Associations[0].AssociationId' --output text --region "$REGION")
aws ssm start-associations-once --association-ids "$ASSOC_ID" --region "$REGION" >/dev/null
sleep 2
EXEC_ID=$(aws ssm describe-association-executions --association-id "$ASSOC_ID" --query 'AssociationExecutions[0].ExecutionId' --output text --region "$REGION")
TARGET_JSON=$(aws ssm describe-association-execution-targets --association-id "$ASSOC_ID" --execution-id "$EXEC_ID" --region "$REGION")
CMD_ID=$(echo "$TARGET_JSON" | jq -r '.AssociationExecutionTargets[0].OutputSource.OutputSourceId')
IID=$(echo "$TARGET_JSON" | jq -r '.AssociationExecutionTargets[0].ResourceId')
while :; do
  STATUS=$(aws ssm get-command-invocation --command-id "$CMD_ID" --instance-id "$IID" --plugin-name "aws:runShellScript" --query 'Status' --output text --region "$REGION" 2>/dev/null || echo InProgress)
  [ "$STATUS" != "InProgress" ] && break
  sleep 2
done
aws ssm get-command-invocation --command-id "$CMD_ID" --instance-id "$IID" --plugin-name "aws:runShellScript" --region "$REGION" --query '{Status:Status,StdOut:StandardOutputContent,StdErr:StandardErrorContent}' --output json
BUCKET=$(aws ssm list-commands --command-id "$CMD_ID" --query 'Commands[0].OutputS3BucketName' --output text --region "$REGION")
PREFIX=$(aws ssm list-commands --command-id "$CMD_ID" --query 'Commands[0].OutputS3KeyPrefix' --output text --region "$REGION")
aws s3 cp "s3://$BUCKET/$PREFIX/$CMD_ID/$IID/awsrunShellScript/0.awsrunShellScript/stdout" ./stdout.last || true
aws s3 cp "s3://$BUCKET/$PREFIX/$CMD_ID/$IID/awsrunShellScript/0.awsrunShellScript/stderr" ./stderr.last || true
echo "stdout: $(pwd)/stdout.last"
echo "stderr: $(pwd)/stderr.last"
