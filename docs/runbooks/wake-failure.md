# Runbook — Wake Failure

## Symptoms
- Wake Lambda returns 500/502.
- EC2 stays in “stopped” or “pending”.
- Wake page shows “Waking failed”.

## Probable Causes
- EC2 IAM profile missing SSM permissions.
- Instance stuck in transitional EC2 state.
- Wake Lambda timeout (cold start too long).
- SSM heartbeat parameter outdated.

## Steps to Diagnose
1. Check Lambda logs:
   ```
   aws logs tail /aws/lambda/helmkube-autowake-wake --follow
   ```
2. Describe EC2 state:
   ```
   aws ec2 describe-instances --instance-ids <ID>
   ```
3. Check SSM parameter heartbeat.
4. Verify IAM trust on Lambda role.

## Mitigation
- Re-run wake API once.
- If stuck: manually start instance:
  ```
  aws ec2 start-instances --instance-ids <ID>
  ```
- Redeploy infra with:
  ```
  terraform apply
  ```

## Permanent Fixes
- Increase wake Lambda timeout.
- Improve transitional-state retry logic.
- Add more granular CloudWatch alerts.
