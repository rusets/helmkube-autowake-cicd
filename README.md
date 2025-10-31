# 🚀 helmkube-autowake-cicd

Spin up a **self-hosted K3s cluster** on AWS EC2 with full Terraform automation,  
auto-wake and auto-sleep Lambdas, Prometheus + Grafana stack, and zero-cost idle mode.  

> 🌐 **Live Demo:** [app.helmkube.site](https://app.helmkube.site)

---

## 📦 What you get

- **K3s cluster** on a single Amazon Linux 2023 EC2 instance.  
- **Helm-deployed Node.js app** (fixed NodePort 30080).  
- **Wake API:** API Gateway → Lambda → Start EC2 → Wait for K3s → Redirect.  
- **Auto-Sleep:** EventBridge Scheduler → Lambda → Stop EC2 after inactivity.  
- **Monitoring:** Prometheus + Grafana (NodePorts 30991 / 30090).  
- **Secure parameters:** stored in AWS SSM (Parameter Store + SecureString).  
- **ECR repository:** for application container images.  
- **Commented Terraform** modules — production-ready & portfolio-friendly.

✅ Zero cost while EC2 is stopped  
✅ Instant wake-up through API Gateway  
✅ Cleanly separated `.tf` modules for real-world readability  

---

## 🧭 Repository structure
```
.
├── app/                     # Demo Node.js app (Dockerized)
├── charts/hello/            # Helm chart for the app
├── infra/
│   ├── ami-and-ec2.tf       # EC2 + EIP + user_data
│   ├── apigw.tf             # API Gateway + Lambdas
│   ├── build-push.tf        # Docker build & push to ECR
│   ├── ecr.tf               # ECR repository
│   ├── helm.tf              # Helm deploy via kubeconfig
│   ├── monitoring.tf        # Prometheus + Grafana
│   ├── iam-*.tf             # IAM roles (EC2, Lambda, Scheduler)
│   ├── ssm.tf               # Heartbeat parameter
│   ├── ssm-deploy.tf        # Optional SSM-based deploy
│   ├── outputs.tf           # Safe outputs only
│   ├── variables.tf         # Variables + validation
│   └── templates/user_data.sh.tmpl
flowchart TD
  user[User Browser] -->|HTTPS| apigw[API Gateway (HTTP)]
  apigw -->|Invoke| wake[Lambda: wake_instance]
  scheduler[EventBridge Scheduler] -->|rate(1m)| sleep[Lambda: sleep_instance]

  wake -->|Start/Describe| ec2[EC2 k3s node]
  sleep -->|Stop| ec2
  wake -->|Read/Write| ssm[SSM Parameter /neon-portfolio/last_heartbeat]
  sleep -->|Read| ssm

  subgraph vpc[VPC]
    ec2 -->|NodePort 30080| svc[Service hello-svc]
    svc --> pod[Pod: hello (Docker)]
    ec2 -.->|kubectl / Helm| helm[Helm chart "hello"]
    ecr[ECR repository] --> pod
    subgraph mon[Monitoring]
      grafana[Grafana (NodePort 30090)]
      prom[Prometheus (NodePort 30991)]
    end
  end

  cw[CloudWatch Logs] <-->|Function logs| wake
  cw <-->|Function logs| sleep
  apigw --> cw
  s3[S3 bucket assoc-logs] -.->|SSM association output| ec2
```

```

---

## 🗺️ Architecture

```mermaid
flowchart LR
  subgraph Client
    U[User\nBrowser]
  end

  U -->|Wake request| APIGW[API Gateway (HTTP API)]
  APIGW --> WAKE[Lambda: wake_instance]
  WAKE --> EC2[(EC2: k3s node)]
  WAKE --> SSM[(SSM Parameter Store)]
  WAKE --> ECR[(ECR: hello image)]
  EC2 -->|Helm deploy| K8S[(k3s cluster)]
  K8S --> SVC[Service NodePort 30080]
  K8S --> PROM[Prometheus 30991]
  K8S --> GRAF[Grafana 30090]

  subgraph Monitoring
    PROM
    GRAF
  end

  subgraph AutoSleep
    EVT[EventBridge Scheduler (1 min)]
    SLP[Lambda: sleep_instance]
  end

  EVT --> SLP
  SLP --> EC2

  classDef infra fill:#0b3d3d,stroke:#0b3d3d,color:#fff
  classDef runtime fill:#0b2a42,stroke:#0b2a42,color:#fff
  class APIGW,WAKE,SLP,EVT,SSM,ECR infra
  class EC2,K8S,SVC,PROM,GRAF runtime
```

**Wake flow:**  
🌐 User → API Gateway → Lambda (wake_instance.py) → Start EC2 → Wait for K3s → Redirect to App  

**Sleep flow:**  
⏰ EventBridge Scheduler → Lambda (sleep_instance.py) → Stop EC2 after `idle_minutes`  

**Monitoring:**  
📊 Prometheus + Grafana (NodePorts) — Grafana admin password stored in SSM.  

---

## ⚙️ Prerequisites
- AWS CLI v2 + Terraform ≥ 1.6  
- IAM permissions for EC2, Lambda, API GW, ECR, SSM  
- Docker for local image build (optional)  
- Existing EIP allocation ID (used in `ami-and-ec2.tf`)  
- Domain (optional): app.helmkube.site  

---

## 🔧 First-time setup

```bash
# Initialize Terraform
cd infra
terraform init

# Apply infrastructure
terraform apply -auto-approve

# (Optional) Build & push image to ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <ACCOUNT>.dkr.ecr.us-east-1.amazonaws.com

docker build -t hello-app:v1.2.1 ./app
docker tag hello-app:v1.2.1 <ACCOUNT>.dkr.ecr.us-east-1.amazonaws.com/helmkube-autowake/hello-app:v1.2.1
docker push <ACCOUNT>.dkr.ecr.us-east-1.amazonaws.com/helmkube-autowake/hello-app:v1.2.1
```

Then visit:  
👉 **http://<ec2-dns>:30080** – your app  
👉 **https://app.helmkube.site** – wake endpoint  

---

## 🤖 GitHub Actions (future-ready)
You can add these workflows easily:

- **CI:** Build & push to ECR  
- **CD:** Terraform apply / destroy + Helm upgrade  
- **OPS:** Wake / Sleep instance via API Gateway  

All jobs can use GitHub OIDC to assume `github-actions-tf-role`.

---

## 🔍 Key variables (from `terraform.tfvars`)

| Name | Type | Default | Description |
|------|------|----------|-------------|
| `project_name` | string | helmkube-autowake | Prefix for AWS resources |
| `region` | string | us-east-1 | AWS region |
| `instance_type` | string | m7i-flex.large | EC2 instance type |
| `admin_ip` | string | your /32 | Restricts Grafana/Prometheus access |
| `node_port` | number | 30080 | App NodePort |
| `grafana_node_port` | number | 30090 | Grafana UI |
| `prometheus_node_port` | number | 30991 | Prometheus UI |
| `idle_minutes` | number | 5 | Auto-sleep delay |
| `use_ssm_deploy` | bool | false | Use SSM kubectl deploy |

---

## 💰 Cost notes
**Idle:**  
  $0 for EC2 (completely stopped)  
  + pennies for Lambda invocations, API GW, CloudWatch, SSM  

**Active:**  
  ~ $0.11/hr for m7i-flex.large instance  
  Minimal storage (SSM + ECR) < $2/mo  

---

## 🆘 Troubleshooting

**K3s API not ready** → Wait 60–90 sec after wake (cloud-init finalizing)  
**Helm timeout** → increase `ready_poll_total_sec` in variables.tf  
**Grafana login** →  
```bash
aws ssm get-parameter   --name /helmkube/grafana/admin_password   --with-decryption
```
**API 403** → verify `aws_lambda_permission` covers `execution_arn /*/*`

---

## 🧹 Cleanup

```bash
# Optional stop
aws ec2 stop-instances --instance-ids <id> --region us-east-1

# Destroy all resources
cd infra
terraform destroy -auto-approve
```

---

## 🖼️ Architecture diagram
