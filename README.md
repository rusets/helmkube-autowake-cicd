# 🚀 Helmkube Autowake — k3s on EC2 with On‑Demand Wake & Auto‑Sleep

Live demo: **https://app.helmkube.site/**

Small, portfolio‑ready platform that runs a Node.js app on a **single k3s node (EC2)**, auto‑builds and stores images in **ECR**, deploys via **Helm**, wakes the stack **on demand** through **API Gateway + Lambda**, and auto‑sleeps the EC2 instance after inactivity via **EventBridge Scheduler + Lambda**. Includes **Prometheus + Grafana** with secure password handling in **SSM**.

> Goal: minimal monthly cost when idle, clean IaC (Terraform), and a neat demo that looks production‑aware.

---

## 📁 Repository Structure (current)
> Tip: show hidden folders with `tree -a -d -L 2`

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
    └── variables.tf
                helm.tf
```

> Full structure (as of this commit):
```
.
├── app
│   ├── Dockerfile
│   ├── package.json
│   ├── public
│   │   ├── img
│   │   ├── index.html
│   │   ├── script.js
│   │   └── styles.css
│   └── server.js
├── charts
│   └── hello
│       ├── Chart.yaml
│       ├── templates
│       │   ├── deployment.yaml
│       │   └── service.yaml
│       └── values.yaml
└── infra
    ├── ami-and-ec2.tf
    ├── apigw.tf
    ├── backend.tf
    ├── build
    │   ├── k3s-embed.yaml
    │   ├── k3s.yaml
    │   ├── sleep_instance.zip
    │   └── wake_instance.zip
    ├── build-push.tf
    ├── datasources.tf
    ├── ecr.tf
    ├── helm.tf
    ├── iam-ec2.tf
    ├── iam-scheduler.tf
    ├── lambda
    │   ├── sleep_instance.py
    │   └── wake_instance.py
    ├── monitoring.tf
    ├── network.tf
    ├── outputs.tf
    ├── providers.tf
    ├── s3-logs.tf
    ├── ssm-deploy.tf
    ├── ssm-logs.tf
    ├── ssm.tf
    ├── templates
    │   └── user_data.sh.tmpl
    ├── terraform.tfvars
    └── variables.tf
```

---

## 🧭 High‑Level Architecture (Mermaid)

```mermaid
graph TD
  A[User / Browser] -->|Open app.helmkube.site| B[API Gateway (HTTP)]
  B -->|Lambda proxy| C[Lambda: wake_instance]
  C -->|Describe + Start| D[(EC2 k3s node)]
  D -->|k3s| E[App Pod (hello)]
  D -->|Helm| F[hello Chart]
  C -->|Optional: refresh ECR secret & kubeconfig| D

  subgraph Monitoring
    G[Prometheus]
    H[Grafana]
  end
  D -->|ServiceMonitor| G
  H -->|Datasource| G

  subgraph Auto-sleep
    I[EventBridge Scheduler (rate 1m)]
    J[Lambda: sleep_instance]
  end
  I --> J
  J -->|Stop when idle| D

  subgraph AWS Artifacts
    K[ECR repo]
    L[SSM Parameter Store]
    M[S3 (assoc logs)]
    N[CloudWatch Logs]
  end

  app[Docker image] -->|push| K
  C --> N
  J --> N
  B --> N
  L -.-> H
```

---

## 💡 What this project does

- **EC2 + k3s**: single node, simple + cheap.
- **ECR**: image registry for the `hello` app.
- **Helm**: installs the app chart with a fixed NodePort.
- **Wake on demand**: HTTP API → Lambda starts EC2, waits for readiness, redirects user.
- **Auto‑sleep**: every minute a scheduler checks a heartbeat and stops EC2 if idle.
- **Observability**: Prometheus + Grafana (admin password in SSM `SecureString`).

---

## 🔑 Live Demo

- **App**: https://app.helmkube.site/  
  If the node is asleep, the first request wakes it and you’ll see the app once ready.

---

## ⚙️ Prerequisites

- AWS account with permissions for EC2, ECR, SSM, API Gateway, Lambda, EventBridge, CloudWatch, S3.
- Terraform **1.6+**
- Docker (for local build/push, optional)
- `awscli` configured (`aws configure`)

Optional but recommended:
- Remote backend (S3 + DynamoDB) already declared in `infra/backend.tf`.
- `tree` CLI for structure previews: `brew install tree`

---

## 🛡️ Security Group — required ports (minimal set)

EC2 k3s node needs:

| Purpose                    | Port   | Source CIDR              |
|---------------------------|--------|--------------------------|
| **App NodePort (public)** | 30080  | `0.0.0.0/0`              |
| **Grafana (admin)**       | 30090  | `your.ip.addr/32`        |
| **Prometheus (admin)**    | 30991  | `your.ip.addr/32`        |
| **k3s API (admin)**       | 6443   | `your.ip.addr/32`        |
| **k3s API (cluster)**     | 6443   | `172.31.0.0/16` (VPC)    |
| **Kubelet metrics**       | 10250  | `172.31.0.0/16` (VPC)    |
| **Egress (all)**          | all    | `0.0.0.0/0`              |

> These are implemented in `infra/network.tf` and driven by `var.admin_ip`, `var.node_port`, `var.grafana_node_port`, `var.prometheus_node_port`.

---

## 🧰 Quickstart (local)

```bash
# 1) Clone
git clone https://github.com/rusets/helmkube-autowake-cicd.git
cd helmkube-autowake-cicd/infra

# 2) Configure vars
#   - Set region, project_name, image_tag, admin_ip, etc. in terraform.tfvars

# 3) Init & plan
terraform init
terraform plan

# 4) Apply infra
terraform apply -auto-approve

# 5) Build & push app image to ECR (optional local way; CI also supported)
#    This is done by null_resource.docker_build_push if Docker is available.
terraform apply -auto-approve

# 6) Wake the stack via the API (open in browser)
#    https://app.helmkube.site/
```

**Check k3s connectivity (after wake):**

```bash
K=infra/build/k3s-embed.yaml
kubectl --kubeconfig "$K" get nodes -o wide
kubectl --kubeconfig "$K" -n default get deploy,svc,pods -o wide
```

**View monitoring UIs (from your admin IP):**

- Grafana: `http://<ec2-public-dns>:30090/`  
  Admin user: `admin`, password from SSM: `/helmkube/grafana/admin_password`  
  (Terraform creates a K8s secret from this value automatically.)

- Prometheus: `http://<ec2-public-dns>:30991/`

---

## 🧪 Useful validation commands

**General app health (from your machine):**
```bash
curl -I http://<ec2-public-dns>:30080/
```

**Prometheus scrape targets (inside cluster via kubectl proxy):**
```bash
K=infra/build/k3s-embed.yaml
kubectl --kubeconfig "$K" -n monitoring port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090
# then open http://127.0.0.1:9090/targets
```

**Grafana creds from SSM (decrypted locally):**
```bash
aws ssm get-parameter \
  --name "/helmkube/grafana/admin_password" \
  --with-decryption \
  --query "Parameter.Value" \
  --output text
```

---

## 🧯 Troubleshooting

- **Mermaid rendering fails on GitHub**  
  Ensure the Mermaid block doesn’t contain special brackets in labels. The diagram above uses safe labels.

- **Prometheus dashboards show “No data”**  
  1) Confirm target endpoints are **UP** on Prometheus `/targets`.  
  2) Ensure SG allows **10250** from VPC CIDR for kubelet and **6443** for k3s API service traffic.  
  3) Wait 1–3 minutes after wake—metrics need time to populate.

- **Forbidden from API Gateway to Lambda**  
  `aws_lambda_permission` must allow `execution_arn/*/*` (already included).

- **Helm chart deploy fails on NodePort**  
  The SSM deploy path force‑recreates `hello-svc` to guarantee a fixed `nodePort` and then applies manifests.

- **Null resource wants replacement**  
  `null_resource` uses `triggers`. Any value change (e.g., `kubeconfig_path`, `image_tag`) forces replacement by design.

---

## 🔐 Sensitive outputs

Some `terraform output` values are masked or omitted by default:
- Public IP/DNS (treat as sensitive in commit messages)
- API endpoints for internal components
- SSM parameter names and values

You can still inspect them locally with `terraform output`.

---

## 📦 Clean up

```bash
cd infra
terraform destroy -auto-approve
```

> If you attached a custom domain in API Gateway, remove API mappings first (or destroy with targeted steps).

---

## 📝 License

MIT
