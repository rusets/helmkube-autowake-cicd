resource "aws_ecr_repository" "hello" {
  name                 = "${var.project_name}/hello-app"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}