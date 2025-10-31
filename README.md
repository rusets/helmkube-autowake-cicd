# 🚀 Helmkube Autowake — k3s on EC2 with ECR, Helm, and Wake/Sleep API

> Minimal, portfolio‑ready stack: a single k3s node on EC2 runs your app via a Helm chart from ECR, **auto‑wakes** on traffic and **auto‑sleeps** when idle. Optional Prometheus + Grafana with fixed NodePorts.

**Live demo:** https://app.helmkube.site/

---

## Architecture (Mermaid)

> If GitHub ever fails to render this, the syntax is valid — open the README in a browser that supports Mermaid rendering.

```mermaid
flowchart TD
  U[Visitor / Client] --> GW[API Gateway (HTTP)]
  GW --> W[Lambda: wake_instance]
  W --> EC2[k3s EC2 (Amazon Linux 2023)]
  EC2 --> APP[Hello Service<br/>NodePort 30080]
  EC2 --> ECR[ECR Repository]

  subgraph MON[Monitoring (optional)]
    P[Prometheus<br/>NodePort 30991]
    G[Grafana<br/>NodePort 30090]
    AM[Alertmanager<br/>NodePort 30992]
  end

  EC2 --> P
  P --> G

  SCHED[EventBridge Scheduler (every 1 min)] --> SLP[Lambda: sleep_instance]
  SLP --> EC2
```

---

## What you get

- **k3s on EC2 (Amazon Linux 2023)** — single node for simplicity and low cost.
- **Hello app via Helm** — container image stored in **ECR**; pull secret is created automatically.
- **Wake endpoint** — **API Gateway (HTTP) → Lambda** starts the EC2 and redirects to the app.
- **Auto‑sleep** — **EventBridge Scheduler → Lambda** stops EC2 after `idle_minutes` with no heartbeat.
- **Optional monitoring** — **kube‑prometheus‑stack** (Prometheus + Grafana + Alertmanager) exposed via fixed NodePorts.
- **Security‑first defaults** — dashboards bound to your `/32` admin IP; app NodePort public; everything else egress‑only.
- **Clean Terraform layout** — providers + variables split; comments explain intent.

---

## Repository structure (focus view)

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

> Note: The actual repo has more files (ECR, API GW, IAM, monitoring, etc.). This section is the **concise overview** you asked for; see `/infra` for the full IaC.

---

## Quick start

### Prerequisites
- AWS account with admin or appropriate IaC permissions
- Terraform **1.6+**
- AWS CLI configured (`aws configure`)
- Docker (optional, for local build/push)  
- A public **Elastic IP** already allocated (module expects an existing EIP)

### Deploy
```bash
cd infra
terraform init
terraform apply -auto-approve
```

### Verify (local checks)
```bash
# kubeconfig is embedded to infra/build/k3s-embed.yaml
kubectl --kubeconfig ./build/k3s-embed.yaml get nodes -o wide
kubectl --kubeconfig ./build/k3s-embed.yaml -n default get svc hello-svc -o wide
```

Open the app:
```
http://<EC2 Public DNS>:30080/
```

Or use the **wake URL** (redirects once the node is ready):
```
https://app.helmkube.site/
```

---

## Ports & URLs

| Component        | Port / Route | Exposure                 | Notes |
|------------------|--------------|--------------------------|------|
| App (Hello)      | **30080**    | Public (0.0.0.0/0)       | NodePort on the k3s node |
| Grafana          | **30090**    | Admin IP only            | Set via `var.grafana_node_port` |
| Prometheus       | **30991**    | Admin IP only            | Set via `var.prometheus_node_port` |
| Alertmanager     | **30992**    | Admin IP only (optional) | Toggle with `var.expose_alertmanager` |
| k3s API          | **6443**     | Admin IP only **and** VPC CIDR | Admin via `/32`, pods via ServiceIP from VPC |
| Kubelet metrics  | **10250**    | VPC CIDR only            | For Prometheus scrape from within the VPC |

**Wake API:** printed in Terraform outputs as `wake_api_url` (you can hide it for public repos).

---

## Security group policy (minimal)

- **Allow** TCP **30080** from `0.0.0.0/0` (App NodePort — public demo).
- **Allow** TCP **6443** from your **`admin_ip` /32** (k3s API — admin only).
- **Allow** TCP **6443** from **VPC CIDR** (pods via ServiceIP).  
- **Allow** TCP **30090**, **30991**, **30992** from your **`admin_ip` /32** (Grafana / Prometheus / Alertmanager).
- **Allow** TCP **10250** from **VPC CIDR** (Kubelet metrics).
- **Egress**: allow all.

All of the above are modeled in Terraform with toggles for exposure and admin IP.

---

## Key Terraform variables

| Name | Default | Purpose |
|------|---------|---------|
| `project_name` | `helmkube-autowake` | Prefix for resource names |
| `region` | `us-east-1` | AWS region |
| `image_tag` | `latest` | App image tag in ECR |
| `node_port` | `30080` | App NodePort |
| `grafana_node_port` | `30090` | Grafana NodePort |
| `prometheus_node_port` | `30991` | Prometheus NodePort |
| `alertmanager_node_port` | `30992` | Alertmanager NodePort |
| `admin_ip` | `null` | Your `/32` for admin‑only services |
| `idle_minutes` | `5` | Auto‑sleep threshold |
| `use_ssm_deploy` | `false` | If `true`, deploy app via SSM `kubectl` on the node |

---

## Outputs (public‑safe)

- `hello_url_hint` — example app URL using the instance Public DNS and `node_port`  
- `region`, `node_port` — convenience values  
- Sensitive/targetable outputs (e.g., **instance IP/DNS**, **ECR repo URL**, **API IDs**) can be **commented out** before publishing. The repo is shipped with safe defaults for public display.

---

## Troubleshooting

- **Mermaid doesn’t render on GitHub** — ensure the fenced block starts with <code>```mermaid</code> and each edge is on its own line (this README follows that).
- **Metrics missing in Grafana** — make sure SG allows **10250** from **VPC CIDR** and Prometheus is reachable at **30991** from your admin IP.
- **App doesn’t pull image** — ECR pull secret `ecr-dockercfg` is auto‑created; verify the role has `AmazonEC2ContainerRegistryReadOnly`.
- **Wake page loops** — increase Lambda readiness budget (`READY_POLL_TOTAL_SEC`) and health timeouts in the Lambda env.

---

## Cleanup

```bash
cd infra
terraform destroy -auto-approve
```

---

## License

MIT
