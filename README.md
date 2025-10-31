# Helmkube Autowake · CI/CD
Wake-on-demand k3s demo on AWS: a small Lambda behind HTTP API wakes an EC2 node that runs k3s. App is deployed via Helm; Prometheus + Grafana are optional. One-node, portfolio‑friendly, and cheap at idle.

**Live demo:** https://app.helmkube.site/

---

## Repository structure (top level)
```text
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
> This is the authoritative structure shown in the repo. (No duplicate trees.)

---

## Architecture (Mermaid)
```mermaid
flowchart TD
  U[Visitor / Client] --> GW[API Gateway (HTTP)]
  GW --> W[Lambda: wake_instance]
  W --> EC2[k3s EC2 (Amazon Linux 2023)]
  EC2 -->|Helm chart| APP[Hello Service<br/>NodePort 30080]
  EC2 --> ECR[ECR Repository]

  subgraph MON[Monitoring (optional)]
    P[Prometheus<br/>NodePort 30991]
    G[Grafana<br/>NodePort 30090]
  end

  EC2 --> P
  P --> G

  SCHED[EventBridge Scheduler (every 1 min)] --> SLP[Lambda: sleep_instance]
  SLP --> EC2
```
> If GitHub fails to render Mermaid, open this README from a browser with Mermaid enabled (it’s valid syntax).

---

## Quick start
```bash
# 1) Prepare Terraform backend (S3 + DynamoDB) if not already
# 2) In ./infra, configure ./terraform.tfvars (region, project_name, admin_ip, node_port, etc.)

cd infra
terraform init -input=false
terraform apply -auto-approve -input=false

# Build & push the app locally (optional; CI also works)
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <ACCOUNT>.dkr.ecr.us-east-1.amazonaws.com
docker build -t hello:latest ../app
docker tag hello:latest <ACCOUNT>.dkr.ecr.us-east-1.amazonaws.com/<project>/hello-app:latest
docker push <ACCOUNT>.dkr.ecr.us-east-1.amazonaws.com/<project>/hello-app:latest

# Helm deploy is driven by Terraform (null_resource helm_deploy_hello)
```

### Verify
```bash
# App (public NodePort)
curl -I http://<EC2-public-dns>:30080/

# k3s API readyz
kubectl --kubeconfig ./build/k3s-embed.yaml get --raw=/readyz

# Monitoring
open http://<EC2-public-dns>:30090/   # Grafana
open http://<EC2-public-dns>:30991/   # Prometheus
```

---

## Security group checklist (minimal)
- **App**: TCP **30080** from `0.0.0.0/0` (public demo)
- **Grafana**: TCP **30090** from **your /32** (admin only)
- **Prometheus**: TCP **30991** from **your /32** (admin only)
- **Alertmanager** (optional): TCP **30992** from **your /32**
- **k3s API**: TCP **6443** from **your /32** (or VPC CIDR for in‑cluster access)
- **Kubelet metrics** (Prometheus scrape): TCP **10250** from **VPC CIDR** (`172.31.0.0/16` on default VPC)
- **Egress**: allow all (SSM, ECR pulls, packages)

> Tighten as needed (e.g., swap `0.0.0.0/0` for CloudFront or your office /32).

---

## Variables (high‑impact)
- `project_name`, `region`
- `admin_ip` and `admin_cidr`
- `node_port`, `grafana_node_port`, `prometheus_node_port`, `alertmanager_node_port`
- `use_ssm_deploy` (SSM–based deploy) vs Helm provider (default)
- `instance_name_tag` (for autodetect), `instance_type`

---

## Cleanup
```bash
cd infra
terraform destroy -auto-approve -input=false
```

---

## License
MIT
