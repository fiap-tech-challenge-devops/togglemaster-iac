
resource "kubernetes_namespace_v1" "argocd" {
  metadata {
    name = var.argocd_namespace
  }
}

locals {
  gitops_repo_is_private = var.gitops_repo_username != null && var.gitops_repo_password != null
}

resource "kubernetes_secret_v1" "gitops_repo" {
  count = local.gitops_repo_is_private ? 1 : 0

  metadata {
    name      = "gitops-repo"
    namespace = kubernetes_namespace_v1.argocd.metadata[0].name

    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
  }

  data = {
    type     = "git"
    url      = var.gitops_repo_url
    username = var.gitops_repo_username
    password = var.gitops_repo_password
  }
}

locals {
  argocd_cm_values = [yamlencode({
    configs = {
      cm = {
        "timeout.reconciliation" = var.argocd_reconciliation_timeout
      }
    }
  })]

  argocd_admin_values = var.argocd_admin_password_bcrypt == "" ? [] : [yamlencode({
    configs = {
      secret = {
        argocdServerAdminPassword      = var.argocd_admin_password_bcrypt
        argocdServerAdminPasswordMtime = "2026-01-01T00:00:00Z"
      }
    }
  })]
}

resource "helm_release" "argocd" {
  name       = "argocd"
  namespace  = kubernetes_namespace_v1.argocd.metadata[0].name
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version

  wait          = true
  wait_for_jobs = true
  timeout       = 900

  values = concat(var.argocd_helm_values, local.argocd_cm_values, local.argocd_admin_values)

  depends_on = [kubernetes_secret_v1.gitops_repo]
}

resource "helm_release" "argocd_apps" {
  name       = "argocd-apps"
  namespace  = kubernetes_namespace_v1.argocd.metadata[0].name
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = var.argocd_apps_chart_version

  values = [
    yamlencode({
      applications = {
        root = {
          namespace = var.argocd_namespace
          project   = "default"

          source = {
            repoURL        = var.gitops_repo_url
            targetRevision = var.gitops_repo_revision
            path           = var.gitops_root_path
          }

          destination = {
            server    = "https://kubernetes.default.svc"
            namespace = var.argocd_namespace
          }

          syncPolicy = {
            automated = {
              prune    = true
              selfHeal = true
            }
            syncOptions = ["CreateNamespace=true"]
          }
        }
      }
    })
  ]

  depends_on = [helm_release.argocd]
}
