# ADR-004 — Security Boundaries & Secrets in SSM

## Status
Accepted

## Context
The system stores kubeconfig, Grafana password, and operational parameters. Hardcoding secrets is unacceptable.

## Decision
Use AWS SSM Parameter Store (SecureString + KMS).

## Rationale
- Zero secrets in Terraform state  
- GitHub Actions OIDC can read/write parameters safely  
- Easy auditability (CloudTrail)  
- Can grow into full parameterized configuration management  

## Consequences
- Requires IAM scoping for Lambda and EC2  
- Parameters must be refreshed during wake/bootstrap  
- KMS access must be tightly controlled
