# **Cost Breakdown**

This project is designed to run near-free when idle.

## **EC2**
- Primary cost driver  
- Auto-stops after idle → $2–$5/mo (depending on wake frequency)

## **Lambda**
- Practically free (wake/sleep functions)

## **API Gateway**
- < $1/mo in typical demo usage

## **S3**
- Pennies per month for SSM logs and Terraform state

## **ECR**
- Only one small demo image → negligible

## **NO NAT Gateway**
- Saves ~$32/month  
- Outbound traffic uses public IP instead

Overall expected monthly cost: **$3–$7**.