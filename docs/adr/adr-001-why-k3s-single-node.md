# ADR-001 — Why Use Single-Node k3s Instead of EKS

## Status
Accepted

## Context
The project requires lightweight, fast‑booting Kubernetes suitable for demos, wake/sleep automation, and portfolio use. EKS is overkill (control-plane pricing, slow cold starts, more moving parts).

## Decision
Use a single Amazon Linux 2023 EC2 instance running k3s.

## Rationale
- Near-zero cost compared to EKS control-plane fees  
- Fast launch time for wake-on-demand architecture  
- Simplified networking (no VPC CNI complexity)  
- Easier to showcase Helm, monitoring, and cluster lifecycle logic  

## Consequences
- Not HA (single node)  
- Not suitable for production workloads  
- Perfect for demo/portfolio use
