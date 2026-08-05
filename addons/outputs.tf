output "installed_addons" {
  description = "Componentes instalados por este stage e a versão do chart de cada um."
  value = merge(
    {
      metrics_server               = helm_release.metrics_server.version
      aws_load_balancer_controller = helm_release.aws_lb_controller.version
      external_secrets             = helm_release.external_secrets.version
      keda                         = helm_release.keda.version
      karpenter                    = helm_release.karpenter.version
      argocd                       = helm_release.argocd.version
    },
    var.enable_cert_manager ? { cert_manager = helm_release.cert_manager[0].version } : {},
    var.enable_kube_prometheus_stack ? { kube_prometheus_stack = helm_release.kube_prometheus_stack[0].version } : {},
  )
}

output "cluster_secret_store_name" {
  description = "Nome do ClusterSecretStore. É o valor de secretStoreRef.name nos ExternalSecrets do repositório GitOps."
  value       = "aws-secrets-manager"
}

output "karpenter_nodepool" {
  description = "NodePool criado e seu teto de vCPU."
  value = {
    name      = "default"
    cpu_limit = var.karpenter_cpu_limit
  }
}

# ── Argo CD ───────────────────────────────────────────────────────────────────
output "argocd_namespace" {
  description = "Namespace onde o Argo CD foi instalado."
  value       = kubernetes_namespace_v1.argocd.metadata[0].name
}

output "gitops_repo_url" {
  description = "Repositório observado pela Application raiz."
  value       = var.gitops_repo_url
}

output "argocd_initial_password_command" {
  description = "Comando para ler a senha inicial do usuário admin do Argo CD."
  value       = "kubectl -n ${var.argocd_namespace} get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}

output "argocd_port_forward_command" {
  description = "Acesso local à interface do Argo CD, enquanto não houver Ingress."
  value       = "kubectl -n ${var.argocd_namespace} port-forward svc/argocd-server 8080:443"
}
