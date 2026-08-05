# ── metrics-server ────────────────────────────────────────────────────────────
# Sem ele o HPA não tem de onde ler CPU e memória, e fica preso em "unknown".
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  namespace  = "kube-system"
  repository = "https://kubernetes-sigs.github.io/metrics-server"
  chart      = "metrics-server"
  version    = var.metrics_server_chart_version

  wait    = true
  timeout = 600
}

# ── AWS Load Balancer Controller ──────────────────────────────────────────────
# É ele que transforma Ingress em ALB. Sem ele, nada do cluster é acessível de
# fora. A IAM role vem do stage infra (módulo eks-aws-lb-controller).
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

      # O webhook intercepta TODO Service do cluster. Antes de os pods do
      # controller ficarem prontos, ele quebra a criação de Services de outros
      # charts com "no endpoints available for aws-load-balancer-webhook-service".
      # Só usamos Ingress, nunca Service type=LoadBalancer — é dispensável.
      enableServiceMutatorWebhook = false
    })
  ]
}

# ── External Secrets Operator ─────────────────────────────────────────────────
# Materializa no cluster os segredos que vivem no Secrets Manager — as connection
# strings dos três RDS e as chaves de aplicação.
resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  namespace        = "external-secrets"
  create_namespace = true
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = var.external_secrets_chart_version

  # wait é obrigatório aqui: o ClusterSecretStore abaixo é um CR da CRD que este
  # chart instala, e o webhook do operator precisa estar respondendo.
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

# O ClusterSecretStore é um CR da CRD que o chart acima acabou de criar.
#
# Com kubernetes_manifest o plan falharia: o provider valida o manifesto contra o
# schema da API antes do apply, e nesse momento a CRD ainda não existe — foi
# exatamente onde a versão anterior deste projeto quebrou. Um chart local resolve
# porque o Helm renderiza e aplica em tempo de apply.
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

# ── KEDA ──────────────────────────────────────────────────────────────────────
# O analytics-service escala pela profundidade da fila SQS, não por CPU. Quem
# consulta a fila é o keda-operator, e por isso a role dele é separada da dos pods.
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

  # O KEDA cria HPAs por baixo dos panos; sem o metrics-server eles não reportam.
  depends_on = [helm_release.metrics_server]
}

# ── Opcionais ─────────────────────────────────────────────────────────────────

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

  # Timeout maior: a stack sobe muitos componentes e puxa imagens grandes.
  wait    = true
  timeout = 1200
}
