############################################
# Terraform Backend — Remote State in S3
############################################
terraform {
  backend "s3" {
    bucket         = "tf-state-helmkube-autowake"
    key            = "helmkube-autowake/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "tf-locks-helmkube-autowake"
  }
}

############################################
# DynamoDB Table — State Locking for Terraform Backend
############################################
resource "aws_dynamodb_table" "tf_locks" {
  name         = "tf-locks-helmkube-autowake"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Project = "helmkube-autowake"
    Managed = "terraform"
  }

  lifecycle {
    prevent_destroy = true
  }
}
