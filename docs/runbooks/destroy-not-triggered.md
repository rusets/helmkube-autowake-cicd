# Runbook — Destroy Not Triggered

## Symptoms
- EC2 stays running after idle window.
- Sleep Lambda does not fire.
- API Gateway shows normal behavior.

## Probable Causes
- EventBridge schedule is disabled.
- Sleep Lambda IAM permission revoked.
- Heartbeat parameter stuck.
- Scheduler time drift.

## Steps to Diagnose
1. Inspect scheduler:
   ```
   aws scheduler list-schedules
   ```
2. Tail sleep Lambda logs:
   ```
   aws logs tail /aws/lambda/helmkube-autowake-sleep --follow
   ```
3. Confirm SSM heartbeat timestamp.
4. Verify sleep Lambda IAM policy.

## Mitigation
- Re-enable schedule.
- Force manual stop:
  ```
  aws ec2 stop-instances --instance-ids <ID>
  ```

## Permanent Fixes
- Add CloudWatch alarm for missing invocations.
- Add auto-repair script inside scheduler.
