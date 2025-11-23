############################################
# S3 Bucket for SSM Association Logs
# Purpose: private log storage for SSM automation (per-instance associations)
############################################
resource "aws_s3_bucket" "assoc_logs" {
  bucket        = "${var.project_name}-assoc-logs"
  force_destroy = true
}

############################################
# S3 Ownership Controls
# Purpose: ensure bucket-owner full control of uploaded log objects
############################################
resource "aws_s3_bucket_ownership_controls" "assoc_logs" {
  bucket = aws_s3_bucket.assoc_logs.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

############################################
# Public Access Block
# Purpose: enforce fully private bucket (no ACLs, no policies, no public access)
############################################
resource "aws_s3_bucket_public_access_block" "assoc_logs" {
  bucket                  = aws_s3_bucket.assoc_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

############################################
# IAM Policy Document for SSM → S3 Logs
# Purpose: allow SSM to put log objects into this bucket
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
# IAM Role Policy Attachment
# Purpose: grant EC2 role the ability to write SSM association logs to S3
############################################
resource "aws_iam_role_policy" "ssm_assoc_s3_logs_attach" {
  name   = "${var.project_name}-ssm-assoc-s3-logs"
  role   = aws_iam_role.ec2_role.id
  policy = data.aws_iam_policy_document.ssm_assoc_s3_logs.json
}
