# **Monitoring Overview**

## **Metrics (Prometheus)**
- Node CPU / Memory
- Pod-level usage
- Network throughput
- k3s API health
- Application service metrics

## **Dashboards (Grafana)**
- Cluster Overview
- Node & Pod Resources
- Workload (hello app)
- Networking (RX/TX)
- Alertmanager metrics

## **Alerting**
- Basic alerting through Alertmanager:
  - Node high CPU
  - Memory saturation
  - Prometheus target down

Monitoring stack is optional and can be disabled via Terraform variables.