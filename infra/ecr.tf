############################################
# ECR Repository — hello-app image storage
# Purpose: stores built Docker images for k3s deployment
############################################
resource "aws_ecr_repository" "hello" {
  name                 = "${var.project_name}/hello-app"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  encryption_configuration {
    encryption_type = "AES256"
  }

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name      = "${var.project_name}-hello-ecr"
    Project   = var.project_name
    Protected = "true"
  }

  lifecycle {
    prevent_destroy = false
  }
}
