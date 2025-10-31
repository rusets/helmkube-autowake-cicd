############################################
# Monitoring — Prometheus + Grafana
# Purpose: one-node observability with admin secret in SSM
############################################

############################################
# Grafana admin password — strong random
############################################
resource "random_password" "grafana_admin" {
  length           = 24
  special          = true
  override_special = "!@#%&*()-_+="
  min_upper        = 1
  min_lower        = 1
  min_numeric      = 1
  min_special      = 1
}

############################################
# Grafana admin password — store in SSM SecureString
############################################
resource "aws_ssm_parameter" "grafana_admin" {
  name        = "/helmkube/grafana/admin_password"
  description = "Grafana admin password (managed by Terraform)"
  type        = "SecureString"
  value       = random_password.grafana_admin.result
  overwrite   = true

  tags = {
    Project = var.project_name
  }
}

############################################
# Grafana admin password — fetch decrypted for K8s Secret
############################################
data "aws_ssm_parameter" "grafana_admin" {
  name            = aws_ssm_parameter.grafana_admin.name
  with_decryption = true
  depends_on      = [aws_ssm_parameter.grafana_admin]
}

############################################
# Kubernetes namespace — monitoring
############################################
resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
    labels = {
      "app.kubernetes.io/name" = "monitoring"
      "managed-by"             = "terraform"
    }
  }

  depends_on = [null_resource.fetch_kubeconfig]
}

############################################
# Kubernetes Secret — grafana-admin (username/password)
############################################
resource "kubernetes_secret" "grafana_admin" {
  metadata {
    name      = "grafana-admin"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }

  data = {
    admin-user     = "admin"
    admin-password = data.aws_ssm_parameter.grafana_admin.value
  }

  type = "Opaque"

  depends_on = [
    null_resource.fetch_kubeconfig,
    data.aws_ssm_parameter.grafana_admin,
    kubernetes_namespace.monitoring
  ]
}

############################################
# Helm — kube-prometheus-stack (Grafana + Prometheus)
############################################
resource "helm_release" "prometheus" {
  depends_on       = [null_resource.fetch_kubeconfig, kubernetes_secret.grafana_admin, kubernetes_namespace.monitoring]
  name             = "prometheus"
  namespace        = kubernetes_namespace.monitoring.metadata[0].name
  create_namespace = false

  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "65.2.0"

  wait             = true
  timeout          = 1200
  atomic           = true
  wait_for_jobs    = true
  recreate_pods    = true
  force_update     = true
  cleanup_on_fail  = true
  disable_webhooks = true
  replace          = true
  reset_values     = true
  reuse_values     = false
  max_history      = 3

  values = [
    yamlencode({
      prometheusOperator = {
        admissionWebhooks = { enabled = false }
        tls               = { enabled = false }
      }

      alertmanager = {
        enabled = true
        service = {
          type     = "NodePort"
          nodePort = 30992
        }
        alertmanagerSpec = {
          replicas = 1
        }
        config = {
          global    = {}
          route     = { receiver = "null" }
          receivers = [{ name = "null" }]
        }
      }

      grafana = {
        admin = {
          existingSecret = "grafana-admin"
          userKey        = "admin-user"
          passwordKey    = "admin-password"
        }

        service = {
          type     = "NodePort"
          nodePort = var.grafana_node_port
        }

        serviceMonitor = { selfMonitor = true }

        env = {
          GF_AUTH_ANONYMOUS_ENABLED = "false"
          GF_USERS_ALLOW_SIGN_UP    = "false"
        }

        "grafana.ini" = {
          date_formats = { default_timezone = "browser" }
          panels       = { disable_sanitize_html = true }
        }

        livenessProbe = {
          httpGet             = { path = "/api/health", port = 3000 }
          initialDelaySeconds = 30
          timeoutSeconds      = 5
          periodSeconds       = 10
          failureThreshold    = 5
        }

        readinessProbe = {
          httpGet             = { path = "/api/health", port = 3000 }
          initialDelaySeconds = 10
          timeoutSeconds      = 5
          periodSeconds       = 10
          failureThreshold    = 6
        }

        startupProbe = {
          httpGet             = { path = "/api/health", port = 3000 }
          initialDelaySeconds = 10
          timeoutSeconds      = 5
          periodSeconds       = 5
          failureThreshold    = 30
        }

        extraInitContainers = [
          { name = "sleep-before-sidecars", image = "busybox:1.36", command = ["sh", "-c", "echo 'Waiting 30s for Grafana...'; sleep 30"] }
        ]

        sidecar = {
          datasources = { enabled = false }
          dashboards = {
            enabled           = true
            label             = "grafana_dashboard"
            searchNamespace   = "ALL"
            folder            = "/var/lib/grafana/dashboards/custom"
            defaultFolderName = "custom"
          }
        }

        downloadDashboards = { enabled = false }

        podAnnotations = {
          secret-hash = "${sha256(data.aws_ssm_parameter.grafana_admin.value)}"
        }

        datasources = {
          "datasources.yaml" = {
            apiVersion = 1
            datasources = [
              {
                name      = "Prometheus"
                type      = "prometheus"
                access    = "proxy"
                url       = "http://prometheus-kube-prometheus-prometheus.monitoring:9090"
                isDefault = true
              }
            ]
          }
        }

        defaultDashboardsEnabled = true
      }

      prometheus = {
        service = {
          type     = "NodePort"
          nodePort = var.prometheus_node_port
        }
      }

      kubelet = {
        serviceMonitor = {
          enabled  = true
          cAdvisor = true
          probes   = true
        }
      }

      defaultRules = { create = true }
    })
  ]
}
