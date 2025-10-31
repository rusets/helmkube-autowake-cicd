# 🚀 Helmkube Autowake — K3s + Lambda + API Gateway

A fully automated, cost-efficient **K3s Kubernetes cluster on AWS** that wakes up on demand and sleeps automatically after inactivity.  
Perfect for personal projects, demos, or portfolios — running for **$0 at idle**.

---

## 🧠 Overview

This stack runs a single-node K3s cluster on EC2, deploys a demo app from ECR via Helm,  
and uses two lightweight Lambda functions to **wake** or **sleep** the instance through API Gateway and EventBridge.

🔹 When idle → Lambda stops EC2.  
🔹 When accessed → Wake API starts EC2 and waits for app readiness.  
🔹 Everything (ECR, SSM, Prometheus, Grafana) managed via Terraform.

Live Demo: [https://app.helmkube.site](https://app.helmkube.site)

---

## 🗺️ Architecture

```mermaid
flowchart LR
  subgraph User
    U[Browser]
  end

  U -->|HTTP /wake| APIGW[API Gateway]
  APIGW --> WAKE[Lambda: wake_instance]
  WAKE --> EC2[(EC2: K3s Node)]
  WAKE --> SSM[(SSM Parameter Store)]
  WAKE --> ECR[(ECR Repository)]
  EC2 -->|Helm Deploy| K3S[(K3s Cluster)]
  K3S --> APP[NodePort Service :30080]
  K3S --> GRAF[Grafana :30090]
  K3S --> PROM[Prometheus :30991]

  subgraph Monitoring
    PROM
    GRAF
  end

  subgraph AutoSleep
    EVT[EventBridge Scheduler (1m)]
    SLP[Lambda: sleep_instance]
  end

  EVT --> SLP --> EC2

  classDef infra fill:#093f48,stroke:#093f48,color:#fff
  classDef runtime fill:#0b2a42,stroke:#0b2a42,color:#fff
  class APIGW,WAKE,SLP,EVT,SSM,ECR infra
  class EC2,K3S,APP,PROM,GRAF runtime
```

---

## ⚙️ Key Features

- 💤 **Auto-sleep / Auto-wake** — EC2 shuts down after `idle_minutes`, wakes via API call  
- 🐳 **ECR-based deployments** — every app version tagged & deployed automatically  
- 📊 **Monitoring stack** — Prometheus + Grafana (NodePort)  
- 🔐 **Secrets in AWS SSM** — passwords never stored in state  
- 🧩 **Full IaC** — 100% Terraform-managed infrastructure  
- 💬 **SSM-only access** — no SSH keys or public ports needed

---

## 📁 Repository Structure

```
helmkube-autowake-cicd/
├── app/                     # Demo app (Dockerized)
├── infra/                   # Terraform modules
│   ├── main.tf
│   ├── variables.tf
│   ├── terraform.tfvars
│   ├── outputs.tf
│   └── templates/
├── lambda/                  # wake_instance.py & sleep_instance.py
└── README.md
```

---

## 🚀 Deployment Steps

```bash
# 1. Initialize Terraform
cd infra
terraform init

# 2. Apply infrastructure
terraform apply -auto-approve

# 3. Fetch kubeconfig (auto)
ls build/k3s-embed.yaml

# 4. Access Grafana / Prometheus
http://<EC2_PUBLIC_DNS>:30090  (Grafana)
http://<EC2_PUBLIC_DNS>:30991  (Prometheus)
```

---

## 🔧 Key Variables

| Name | Type | Default | Description |
|------|------|----------|-------------|
| `region` | string | us-east-1 | AWS region |
| `instance_type` | string | m7i-flex.large | EC2 size |
| `node_port` | number | 30080 | App NodePort |
| `grafana_node_port` | number | 30090 | Grafana NodePort |
| `prometheus_node_port` | number | 30991 | Prometheus NodePort |
| `admin_ip` | string | `x.x.x.x/32` | Restrict dashboards |
| `idle_minutes` | number | 5 | Idle timeout before stop |
| `use_ssm_deploy` | bool | false | Deploy via SSM (kubectl) or local Helm |
| `project_name` | string | helmkube-autowake | Resource prefix |

---

## 🌍 Live Demo

🟢 **Visit:** [https://app.helmkube.site](https://app.helmkube.site)  
⏱️ *Starts EC2 automatically, initializes K3s, and redirects to your app.*

---

## 💰 Cost Breakdown

| State | Components | Approx. Monthly Cost |
|--------|-------------|----------------------|
| **Idle** | S3, DynamoDB, Lambdas, API GW | <$0.50 |
| **Running** | EC2 (m7i-flex.large) | ~$15/month |

---

## 🧩 Future Enhancements

- ✅ Add CloudWatch alarms for uptime tracking  
- ✅ CI/CD pipeline with GitHub Actions (build → ECR → Terraform apply)  
- ⏳ Optional Route53 automation with ACM cert  

---

## 📝 License

MIT — Created by [Ruslan Dashkin](https://github.com/rusets)
