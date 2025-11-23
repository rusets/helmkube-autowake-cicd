# Copilot Instructions for this Repository

These guidelines define how GitHub Copilot must generate code, configuration, and documentation inside this project.

## ==========================
## 1. Terraform Style Rules
## ==========================

### 1. Always use multi-line Terraform blocks
- No single-line resource or data blocks.
- Every argument must be on its own line.
- Closing bracket (`}`) must be on a new line.
- Arrays and maps must also be multi-line.

### 2. Add header comments above each Terraform resource
Header format:

############################################
# <Component / Purpose>
# <Short description of why this resource exists>
############################################

- Do NOT use inline comments.
- Do NOT put comments inside blocks.
- All comments must be ABOVE the resource or below the code block (never inside).

### 3. Never use SSH key pairs
- Do NOT add `key_name`.
- All EC2 access should be done via SSM Session Manager only.

### 4. Secrets handling
- Never store secrets in Terraform variables.
- Never propose storing passwords in `terraform.tfvars`.
- RDS passwords must use `manage_master_user_password = true`.
- Application passwords must be stored in AWS SSM Parameter Store (`SecureString`).
- Bootstrap scripts must read secrets from SSM via instance role.

### 5. Respect existing user_data
- Never replace or rewrite the user's application code inside `user_data.sh`.
- Only modify bootstrap logic (install packages, fetch secrets).
- Never suggest overwriting user scripts.

### 6. Remote state rules
- Always use S3 backend with DynamoDB lock.
- Never propose local state.
- Never create or modify backend configuration dynamically.

### 7. Kubeconfig paths (repository-relative)
Copilot must use ONLY these two kubeconfig files within this repo:

- `infra/build/k3s.yaml`
- `infra/build/k3s-embed.yaml`

Rules:
- Never suggest `~/.kube/config` unless explicitly requested.
- Never invent alternative paths.
- Never reference `/tmp`, `/etc/kubernetes`, or system paths.

### 8. K3s cluster rules
- Always include wait logic before deploying Helm charts.
- Must verify API is ready before running helm or kubectl.
- Use Terraform Helm provider whenever possible.

---

## ==========================
## 2. YAML & Kubernetes Rules
## ==========================

### 1. English-only comments
- No Russian comments ever.
- Comments must be concise and clearly describe intent.

### 2. Maintain separation of components
- No combining unrelated manifests.
- Namespace declarations must not be embedded inside workload YAML.

### 3. Helm chart modifications
- Respect existing structure.
- Never suggest creating placeholder charts.
- Never suggest modifying templates that are not part of this repo.

---

## ==========================
## 3. GitHub Actions Style Rules
## ==========================

### 1. Use GitHub OIDC for AWS authentication
- No AWS access keys.
- Never store AWS credentials in secrets.
- Always use `id-token: write` + role assumption.

### 2. Workflow clarity
- Steps must use multi-line YAML where appropriate.
- No inline comments.
- Comments only above blocks.

### 3. CI/CD workflow rules
- Use Terraform fmt, validate, tflint, tfsec for PRs.
- For deploy workflows, always run:
  - `terraform init`
  - `terraform plan`
  - `terraform apply -auto-approve`

---

## ==========================
## 4. Bash/Shell Script Rules
## ==========================

### 1. No comments inside code blocks in answers
- All explanation must go AFTER the code block.

### 2. No replacing user bootstrap logic
- Only add missing steps.
- Never remove or restructure user scripts.

---

## ==========================
## 5. Repository Structure Rules
## ==========================

- Respect existing `infra/` layout.
- Never suggest creating new folders unless explicitly requested.
- Avoid generating placeholder modules.
- Use only real paths from this repo.

---

## ==========================
## 6. General Behavior Rules
## ==========================

### 1. Generate production-quality code
- Clean, readable, consistent.
- No shortcuts or “quick examples”.

### 2. Keep explanations short and technical
- No fluff.
- No teaching tone unless asked.

### 3. Never suggest practices that contradict AWS best practices
Examples:
- Hardcoding credentials → forbidden  
- Publicly exposed secrets → forbidden  
- Plaintext passwords in user_data → forbidden  

### 4. Maintain consistency with user’s long-term preferences:
- Multi-line Terraform.
- Header comments above resources.
- English-only comments in YAML.
- SSM for secrets.
- No key pairs.
- No inline comments in code blocks.
- All explanations after code blocks.

---

# End of Instructions