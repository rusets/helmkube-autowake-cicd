############################################
# Local Docker build & push to ECR (optional)
# Triggers: image_tag, ECR repo URL, app/Dockerfile, package.json, .dockerignore
# Behavior: skips gracefully if docker/daemon/AWS CLI not available
############################################
resource "null_resource" "docker_build_push" {
  triggers = {
    image_tag       = var.image_tag
    ecr_repo_url    = aws_ecr_repository.hello.repository_url
    dockerfile_md   = filesha256("${path.module}/../app/Dockerfile")
    app_md          = filesha256("${path.module}/../app/package.json")
    dockerignore_md = try(filesha256("${path.module}/../app/.dockerignore"), "")
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOC
      set -euo pipefail

      REPO="${aws_ecr_repository.hello.repository_url}"
      TAG="${var.image_tag}"
      REGISTRY="$(echo "$REPO" | cut -d/ -f1)"

      if ! command -v docker >/dev/null 2>&1; then
        echo "[skip] docker CLI not found locally; skipping local build/push"
        exit 0
      fi
      if ! docker info >/dev/null 2>&1; then
        echo "[skip] docker daemon is not running; skipping local build/push"
        exit 0
      fi
      if ! command -v aws >/dev/null 2>&1; then
        echo "[skip] AWS CLI not found; skipping local build/push"
        exit 0
      fi

      echo "[login to ECR]"
      aws ecr get-login-password --region ${var.region} \
        | docker login --username AWS --password-stdin "$REGISTRY"

      echo "[ensure buildx]"
      if ! docker buildx version >/dev/null 2>&1; then
        echo "Docker Buildx is required (Docker Desktop or buildx plugin)."
        exit 1
      fi

      BUILDER_NAME="helmkube-builder"
      if ! docker buildx inspect "$BUILDER_NAME" >/dev/null 2>&1; then
        docker buildx create --name "$BUILDER_NAME" --use >/dev/null
      else
        docker buildx use "$BUILDER_NAME" >/dev/null
      fi

      docker run --privileged --rm tonistiigi/binfmt --install all >/dev/null 2>&1 || true

      echo "[buildx build linux/amd64 and push]"
      docker buildx build \
        --platform linux/amd64 \
        -t "$REPO:$TAG" \
        -f "${path.module}/../app/Dockerfile" \
        "${path.module}/../app" \
        --push

      echo "[done] pushed image: $REPO:$TAG"
    EOC
  }
}
