# **Project Architecture Overview**
```

helmkube-autowake-cicd
├── .github/
│   ├── ISSUE_TEMPLATE/              # GitHub issue templates (bug/feature)
│   │   ├── bug_report.md
│   │   └── feature_request.md
│   ├── PULL_REQUEST_TEMPLATE.md     # Pull Request template
│   └── workflows/
│       ├── deploy.yml               # Deploy full stack (apply)
│       ├── destroy.yml              # Manual safe destroy
│       └── terraform-ci.yml         # terraform fmt/validate + tflint + tfsec + checkov
│
├── app/
│   ├── Dockerfile
│   ├── package.json
│   ├── server.js                    # Demo Node.js app (hello service)
│   └── public/                      # Static assets for the app UI
│       ├── index.html
│       ├── script.js
│       └── styles.css
│
├── build/                           # Generated artifacts (kubeconfig, Lambda ZIPs) — ignored by Git
│   ├── k3s-embed.yaml               # Kubeconfig for local kubectl access
│   ├── k3s.yaml                     # Raw kubeconfig from cluster
│   ├── sleep_instance.zip           # Packaged Lambda (sleep_instance)
│   └── wake_instance.zip            # Packaged Lambda (wake_instance)
│
├── charts/
│   └── hello/                       # Helm chart for k3s demo app
│       ├── Chart.yaml
│       ├── templates/
│       └── values.yaml
│
├── docs/
│   ├── adr/                         # Architectural decision records (ADRs)
│   │   ├── adr-001-why-k3s-single-node.md
│   │   ├── adr-002-why-terraform-for-iac.md
│   │   ├── adr-003-wake-sleep-lifecycle-design.md
│   │   └── adr-004-security-boundaries-and-ssm.md
│   ├── architecture.md              # High-level architecture overview
│   ├── cost.md                      # Cost model & savings
│   ├── diagrams/                    # Mermaid diagrams (arch + sequence)
│   │   ├── architecture.md
│   │   └── sequence.md
│   ├── monitoring.md                # Prometheus/Grafana/Alertmanager docs
│   ├── runbooks/                    # Ops runbooks (wake failure, rollback, etc.)
│   │   └── runbooks.zip
│   ├── screenshots/                 # Evidence: Grafana/Prometheus/kubectl, etc.
│   │   ├── ec2-describe-instance.png
│   │   ├── grafana-alertmanager-overview.png
│   │   ├── grafana-cluster-overview.png
│   │   ├── grafana-networking-cluster.png
│   │   ├── grafana-node-pods.png
│   │   ├── grafana-workload-hello.png
│   │   ├── kubectl-nodes-pods.png
│   │   ├── kubectl-services.png
│   │   ├── prometheus-targets.png
│   │   └── security-group-inbound.png
│   ├── slo.md                       # Wake latency / readiness SLOs
│   └── threat-model.md              # Threat model & security boundaries
│
├── infra/                           # Terraform IaC (core platform)
│   ├── ami-and-ec2.tf               # EC2 + AMI (AL2023) + instance profile
│   ├── apigw.tf                     # API Gateway HTTP routes (/wake, /status)
│   ├── backend.tf                   # S3 backend + DynamoDB state locking
│   ├── build-push.tf                # ECR image build & push wiring
│   ├── ecr.tf                       # ECR repository for app image
│   ├── helm.tf                      # Helm releases (hello app + monitoring)
│   ├── iam-ec2.tf                   # EC2 IAM role / policies
│   ├── iam-scheduler.tf             # EventBridge scheduler role / policies
│   ├── lambda-packaging.tf          # archive_file ZIPs for wake/sleep Lambdas
│   ├── monitoring.tf                # Prometheus/Grafana/Alertmanager stack
│   ├── network.tf                   # Security groups, ports, admin IP logic
│   ├── outputs.tf                   # Terraform outputs (URLs, IDs, etc.)
│   ├── providers.tf                 # Providers + required versions
│   ├── s3-logs.tf                   # S3 bucket for SSM association logs
│   ├── ssm.tf                       # SSM parameters (kubeconfig, passwords)
│   ├── ssm-deploy.tf                # SSM association to bootstrap k3s + Helm
│   ├── ssm-logs.tf                  # CloudWatch log groups for SSM runs
│   └── variables.tf                 # Input variables for the stack
│
├── lambda/
│   ├── sleep_instance.py            # Auto-sleep logic (idle reaper)
│   └── wake_instance.py             # Wake + healthcheck + heartbeat
│
├── templates/
│   └── user_data.sh.tmpl            # EC2 cloud-init / k3s bootstrap script
│
├── wait-site/
│   └── index.html                   # Static wait page (CloudFront + S3 origin)
│
├── .gitignore
├── .tflint.hcl                      # TFLint rules/config
├── copilot-instructions.md          # Notes for GitHub Copilot
├── LICENSE
└── README.md
```

This project runs a lightweight, production-inspired Kubernetes environment on a single EC2 instance.

## **High-Level Flow**
- User hits the Wake API (API Gateway → Lambda)
- Lambda starts the EC2 instance and waits for readiness
- k3s starts → SSM applies Helm deployments (hello + monitoring)
- Optional monitoring stack (Prometheus, Grafana, Alertmanager)
- EventBridge scheduler triggers Sleep Lambda to shut down the instance when idle

## **AWS Components**
- EC2 (Amazon Linux 2023, k3s)
- Lambda (wake / sleep)
- API Gateway HTTP endpoint
- EventBridge Scheduler
- S3 (SSM logs)
- ECR (application images)
- IAM (least-privilege roles)
- SSM Parameter Store (secrets & configs)

## **Kubernetes Components**
- k3s (single-node)
- Demo app (NodePort)
- Monitoring stack (optional)

## **Key Architecture Goals**
- Minimal cost
- Fast wake/sleep lifecycle
- Clean IaC structure
- Small footprint for demos/interviews