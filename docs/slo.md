# **Service Level Objectives (SLO)**

## **1. Availability**
- **Wake API:** 99% successful responses over 30-day window  
- **k3s Node:** starts within **3 minutes** in 90% of wake requests

## **2. Performance**
- App responds within **<500ms** on warmed node  
- Cold start: app becomes reachable in **<45 seconds** after k3s is ready

## **3. Reliability**
- Monitoring stack (if enabled): all Prometheus targets must remain **UP > 95%**

## **4. Error Budget**
- 1% monthly allowance for:
  - Lambda cold starts
  - EC2 transitional states
  - Network warm-ups

These SLOs reflect a demo environment, not a production SLA.