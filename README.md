# Helmkube Autowake — k3s on EC2 with Wake/Sleep

**Live demo:** https://app.helmkube.site/

## Architecture (Mermaid)

```mermaid
flowchart TD
  U[Visitor] --> GW[API Gateway HTTP];
  GW --> W[Lambda wake_instance];
  W --> EC2[k3s EC2];
  EC2 --> APP[Hello Service NodePort 30080];
  EC2 --> ECR[ECR Repository];

  subgraph Monitoring
    P[Prometheus NodePort 30991];
    G[Grafana NodePort 30090];
    P --> G;
  end

  EC2 --> P;
  SCHED[EventBridge Scheduler every 1 min] --> SLP[Lambda sleep_instance];
  SLP --> EC2;
```

> If GitHub fails to render Mermaid in your browser, the syntax above is still valid; try viewing on the GitHub web UI or enable Mermaid support.

## Project structure

```
.
├── .git
├── .github
├── app
│   └── public
├── charts
│   └── hello
└── infra
    ├── build
    ├── lambda
    ├── templates
    ├── providers.tf
    ├── variables.tf
    └── helm.tf
```

## Quick start

```bash
# 1) Build & push the demo image to ECR (optional if already pushed)
cd infra
terraform init
terraform apply -auto-approve
```

## Notes
- NodePort for app: **30080**
- Grafana NodePort: **30090** (admin only, restrict in SG)
- Prometheus NodePort: **30991** (admin only, restrict in SG)
- Alertmanager NodePort: **30992** if enabled (admin only)
