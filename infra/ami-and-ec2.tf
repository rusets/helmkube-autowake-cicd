resource "aws_instance" "k3s" {
  ami                         = data.aws_ssm_parameter.al2023_latest.value
  instance_type               = var.instance_type
  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.k3s_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name
  associate_public_ip_address = true

  # IMDSv2 включён, чтобы user_data мог безопасно читать метаданные (публичный DNS).
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  # Шаблон НЕ должен содержать неэкранированные bash-переменные вида ${VAR:-}.
  # Внутри шаблона используйте $${VAR:-} (см. комментарии ниже).
  user_data = templatefile("${path.module}/templates/user_data.sh.tmpl", {
    project_name = var.project_name
    region       = var.region
    github_org   = var.github_org
    github_repo  = var.github_repo
    ecr_repo     = aws_ecr_repository.hello.repository_url
    image_tag    = var.image_tag
    node_port    = var.node_port
  })

  # Пересоздание инстанса при изменении скрипта cloud-init
  user_data_replace_on_change = true

  lifecycle {
    # SSM-параметр с AMI «движется» вперёд — не хотим дрейфа из-за обновления значения
    ignore_changes = [ami]
  }

  tags = {
    Name       = "${var.project_name}-ec2"
    Project    = var.project_name
    GitHubRepo = var.github_repo
    GitHubOrg  = var.github_org
  }
}