resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  namespace  = "kube-system"
  repository = "https://kubernetes-sigs.github.io/metrics-server"
  chart      = "metrics-server"
  version    = var.metrics_server_chart_version

  wait    = true
  timeout = 600
}

resource "helm_release" "aws_lb_controller" {
  name       = "aws-load-balancer-controller"
  namespace  = "kube-system"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.aws_lb_controller_chart_version

  wait    = true
  timeout = 600

  values = [
    yamlencode({
      clusterName = local.cluster_name
      vpcId       = local.vpc_id
      region      = var.region

      serviceAccount = {
        create = true
        name   = "aws-load-balancer-controller"
        annotations = {
          "eks.amazonaws.com/role-arn" = local.lb_controller_role_arn
        }
      }

      enableServiceMutatorWebhook = false
    })
  ]
}

resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  namespace        = "external-secrets"
  create_namespace = true
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = var.external_secrets_chart_version

  wait    = true
  timeout = 600

  values = [
    yamlencode({
      installCRDs = true

      serviceAccount = {
        annotations = {
          "eks.amazonaws.com/role-arn" = local.external_secrets_role_arn
        }
      }
    })
  ]
}

resource "helm_release" "cluster_secret_store" {
  name      = "cluster-secret-store"
  namespace = "external-secrets"
  chart     = "${path.module}/charts/cluster-secret-store"

  values = [
    yamlencode({
      region             = var.region
      serviceAccountName = "external-secrets"
      namespace          = "external-secrets"
    })
  ]

  depends_on = [helm_release.external_secrets]
}

resource "helm_release" "keda" {
  name             = "keda"
  namespace        = "keda"
  create_namespace = true
  repository       = "https://kedacore.github.io/charts"
  chart            = "keda"
  version          = var.keda_chart_version

  wait    = true
  timeout = 600

  values = [
    yamlencode({
      serviceAccount = {
        operator = {
          annotations = {
            "eks.amazonaws.com/role-arn" = local.keda_role_arn
          }
        }
      }
    })
  ]

  depends_on = [helm_release.metrics_server]
}

resource "helm_release" "cert_manager" {
  count = var.enable_cert_manager ? 1 : 0

  name             = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = var.cert_manager_chart_version

  wait    = true
  timeout = 600

  values = [
    yamlencode({ installCRDs = true })
  ]
}

resource "helm_release" "kube_prometheus_stack" {
  count = var.enable_kube_prometheus_stack ? 1 : 0

  name             = "kube-prometheus-stack"
  namespace        = "monitoring"
  create_namespace = true
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = var.kube_prometheus_stack_chart_version

  wait    = true
  timeout = 1200
}
