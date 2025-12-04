# **Threat Model (Basic)**

## **Assets**
- IAM roles / permissions
- EC2 instance + k3s workloads
- SSM Parameters (passwords, configs)
- Lambda functions (wake/sleep)
- API Gateway endpoint

## **Primary Threats**
- Unauthorized EC2 start/stop  
- Exposure of NodePort services  
- Misconfigured IAM permissions  
- Secrets leakage from SSM  
- Public API misuse (wake spam)

## **Mitigations**
- IAM least-privilege roles
- API Gateway auth via random wake endpoint URL
- SSM Parameter Store with no plaintext in Terraform state
- NodePort access restricted to admin IP (except demo app)
- Logging enabled for SSM, Lambda, and API Gateway

## **Risk Level**
Medium — acceptable for demo/portfolio use, **not** production-grade.