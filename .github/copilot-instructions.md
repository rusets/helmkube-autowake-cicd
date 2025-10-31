## Quick context

This repository contains infrastructure and Kubernetes configuration for the "helmkube-autowake-cicd" project. Primary artifacts observed in the workspace:

- `infra/versions.tf` — sets Terraform required version and provider constraints (Terraform >= 1.5.0; providers: aws >= 5.40.0, kubernetes >= 2.29.0, helm >= 2.10.1).
- `k3s.yaml`, `k3s-embed.yaml` — kubeconfig-like manifests (present at repo root in this workspace snapshot). Use these as the cluster credentials when running kubectl/helm.

If you are an AI coding assistant: use these concrete pieces as your source of truth when making infra-related edits or recommending CLI commands.

## Big-picture architecture (what matters)

- This repo is infra-focused: Terraform drives resources and Helm/kubernetes providers are in use. Expect Terraform code under `infra/` and kubeconfig manifests at the repo root.
- Providers in `infra/versions.tf` imply multi-tool interactions: changes to Terraform may affect AWS resources, Kubernetes in-cluster resources, and Helm releases. Coordinate changes accordingly.

## Common developer workflows and valid commands

- Initialize Terraform (from the `infra/` directory):

  - `cd infra && terraform init` (use `-upgrade` when updating provider pins)
  - `terraform plan -out=tfplan` then `terraform apply tfplan`

- Use the repo kubeconfigs explicitly — do not assume a local default cluster:

  - `KUBECONFIG=$(pwd)/k3s.yaml kubectl get ns`
  - `KUBECONFIG=$(pwd)/k3s-embed.yaml helm list --kubeconfig=$(pwd)/k3s-embed.yaml`

- Helm operations should be executed against the kubeconfig present in repo root when working with this project.

## Project-specific conventions and patterns

- Provider constraints are authoritative: always respect the versions defined in `infra/versions.tf` when editing Terraform files or suggesting version bumps.
- Prefer explicit kubeconfig usage in commands (`--kubeconfig` or `KUBECONFIG=`) rather than assuming `kubectl` context. The repo includes `k3s*.yaml` files — reference them directly.
- Treat `infra/` as the single source for Terraform state and configuration. If you add modules or new providers, also update `infra/versions.tf`.

## Integration points & external dependencies

- AWS: the `aws` provider is present — changes may require AWS credentials (env vars or a profile). Do not embed secrets in code.
- Kubernetes/Helm: Terraform may interact with the cluster via the `kubernetes` and `helm` providers. Provider authentication will typically rely on kubeconfig files (see root `k3s*.yaml`).

## Examples the agent can use when producing edits

- When adding a new provider constraint: update `infra/versions.tf` and explain the compatibility reason (e.g., "bump aws provider to X because of feature Y").
- When changing in-cluster resources: add/modify a Terraform `helm_release` or `kubernetes_manifest` and provide the explicit `--kubeconfig` example to test locally.

## Things NOT to assume

- There is no discovered CI/CD pipeline file in the workspace snapshot. Do not add CI changes without asking where pipeline definitions live (GitHub Actions, GitLab CI, CircleCI, etc.).
- Don't assume a remote backend for Terraform state — verify `infra/` backend configuration before suggesting remote-state changes.

## Where to look next (key files to open)

- `infra/versions.tf` — provider & Terraform constraints (already present)
- `infra/` directory — terraform code and modules (start here for infra changes)
- `k3s.yaml` / `k3s-embed.yaml` — kubeconfigs used for local cluster access

## If you need more context

- Ask the repo owner for:
  - exact Terraform backend configuration and credential setup
  - location of the Helm charts (if not in this repo) and the CI pipeline definition

---
If anything here is unclear or you want the instructions to include more specifics (CI commands, Terraform backend, helm chart locations), tell me which pieces are missing and I will iterate.
