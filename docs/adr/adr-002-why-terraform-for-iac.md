# ADR-002 — Why Terraform for Infrastructure as Code

## Status
Accepted

## Context
Infrastructure must be reproducible, readable, modular, and compatible with GitHub Actions OIDC.

## Decision
Use Terraform as the core IaC engine.

## Rationale
- Strong AWS provider coverage  
- Rich ecosystem (tflint, tfsec, fmt, plan/apply automation)  
- State stored in S3 with DynamoDB locking  
- Great fit for GitHub Actions and CI security scanning  

## Consequences
- Requires state backend  
- Must manage policy‑as‑code and formatting standards  
- Provides professional, production‑grade IaC structure
