# Runbook — Rollback Procedure

## When to Roll Back
- Failed deployment after Terraform apply.
- Wake or sleep Lambda breaking changes.
- k3s bootstrap fails or cluster not ready.
- Helm deployment errors.

## Rollback Types
- **Terraform rollback:** revert IaC changes.
- **Lambda rollback:** restore previous ZIP.
- **Helm rollback:** revert last release revision.

## Steps for Terraform Rollback
1. Checkout previous commit:
   ```
   git checkout <stable-commit>
   ```
2. Re-apply:
   ```
   terraform apply
   ```

## Steps for Lambda Rollback
1. Upload previous ZIP from `infra/build`.
2. Re-publish version:
   ```
   aws lambda update-function-code ...
   ```

## Steps for Helm Rollback
1. View history:
   ```
   helm history hello
   ```
2. Roll back:
   ```
   helm rollback hello <revision>
   ```

## Verification
- Wake API works.
- k3s node ready.
- App reachable on NodePort.

## Preventive Measures
- Enable CI gating with tfsec + tflint.
- Add staging branch for infra changes.
- Maintain Lambda versioning.
