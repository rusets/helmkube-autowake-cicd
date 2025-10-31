############################################
# S3 bucket for SSM association logs (private)
# - Name: <project>-assoc-logs
# - Force destroy for easy teardown in demos
############################################
resource "aws_s3_bucket" "assoc_logs" {
  bucket        = "${var.project_name}-assoc-logs"
  force_destroy = true
}

############################################
# Ownership controls — bucket owner preferred
############################################
resource "aws_s3_bucket_ownership_controls" "assoc_logs" {
  bucket = aws_s3_bucket.assoc_logs.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

############################################
# Block all public access (defense in depth)
############################################
resource "aws_s3_bucket_public_access_block" "assoc_logs" {
  bucket                  = aws_s3_bucket.assoc_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

############################################
# IAM policy doc — allow writes/listing for logs
############################################
data "aws_iam_policy_document" "ssm_assoc_s3_logs" {
  statement {
    actions = [
      "s3:PutObject",
      "s3:PutObjectAcl",
      "s3:GetBucketLocation",
      "s3:ListBucket"
    ]
    resources = [
      aws_s3_bucket.assoc_logs.arn,
      "${aws_s3_bucket.assoc_logs.arn}/*"
    ]
  }
}

############################################
# Attach policy to EC2 role used by SSM association
############################################
resource "aws_iam_role_policy" "ssm_assoc_s3_logs_attach" {
  name   = "${var.project_name}-ssm-assoc-s3-logs"
  role   = aws_iam_role.ec2_role.id
  policy = data.aws_iam_policy_document.ssm_assoc_s3_logs.json
}
