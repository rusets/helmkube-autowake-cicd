# ADR-003 — Wake/Sleep Lifecycle Architecture

## Status
Accepted

## Context
The environment must remain low‑cost while supporting on‑demand demos. EC2 must be stopped when idle and resumed via simple HTTP request.

## Decision
Use Lambda (wake & sleep), API Gateway, and EventBridge Scheduler.

## Rationale
- Fully serverless control plane  
- No NAT Gateway required  
- Minimal cost (Lambda + API Gateway HTTP API)  
- Works reliably with warm/cold EC2 states  
- Easy GitHub Actions integration for updates  

## Consequences
- Stateless Lambdas must handle transitional EC2 states  
- Monitoring stack may require warm-up after wake  
- Requires IAM fine‑tuning for Lambda → EC2 → SSM
