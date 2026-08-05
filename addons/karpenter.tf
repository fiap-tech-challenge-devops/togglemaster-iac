# O plano AWS do Karpenter (role dos nós, IRSA do controller, fila de interrupção
# e regras do EventBridge) é criado no stage infra, pelo módulo eks-karpenter.
# Aqui fica só o chart e os CRs que ele consome.
resource "helm_release" "karpenter" {
  name       = "karpenter"
  namespace  = "kube-system"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = local.karpenter_chart_version

  wait    = true
  timeout = 600

  values = [
    yamlencode({
      settings = {
        clusterName       = local.cluster_name
        interruptionQueue = local.karpenter_interruption_queue
      }

      serviceAccount = {
        name = "karpenter"
        annotations = {
          "eks.amazonaws.com/role-arn" = local.karpenter_controller_role_arn
        }
      }

      # Uma réplica. O chart sobe o controller em HA com anti-affinity REQUIRED
      # por hostname, o que força um segundo nó só para a segunda réplica — e o
      # baseline é de um nó. Sem HA, o controller cabe no nó existente.
      replicas = 1
    })
  ]
}

# NodePool e EC2NodeClass. Sem eles o controller sobe e não provisiona nada.
#
# Chart local pelo mesmo motivo do ClusterSecretStore: são CRs de CRDs criadas no
# apply acima, e o provider kubernetes validaria os manifestos no plan.
resource "helm_release" "karpenter_resources" {
  name      = "karpenter-resources"
  namespace = "kube-system"
  chart     = "${path.module}/charts/karpenter-resources"

  values = [
    yamlencode({
      clusterName = local.cluster_name
      nodeRole    = local.karpenter_node_role_name

      capacityTypes      = var.karpenter_node_capacity_types
      instanceCategories = var.karpenter_node_instance_categories
      cpuLimit           = var.karpenter_cpu_limit
    })
  ]

  depends_on = [helm_release.karpenter]
}
