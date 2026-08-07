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

      replicas = 1
    })
  ]
}

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
