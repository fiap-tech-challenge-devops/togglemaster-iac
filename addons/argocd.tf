# Argo CD — dono dos cinco microsserviços, e só deles.
#
# A plataforma inteira acima é gerenciada pelo Terraform. O Argo CD não conhece
# nenhum daqueles charts, então não há dois controladores disputando o mesmo
# recurso. O repositório GitOps contém apenas os manifests das aplicações.

resource "kubernetes_namespace_v1" "argocd" {
  metadata {
    name = var.argocd_namespace
  }
}

locals {
  # Presença dos dois campos define se o repositório é privado. Um público não
  # precisa de credencial nenhuma.
  gitops_repo_is_private = var.gitops_repo_username != null && var.gitops_repo_password != null
}

# Precisa existir ANTES do chart: o Argo CD lê os Secrets com este label na
# inicialização. Criado depois, a Application raiz falha com "repository not
# accessible" até o próximo reconcile.
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

resource "helm_release" "argocd" {
  name       = "argocd"
  namespace  = kubernetes_namespace_v1.argocd.metadata[0].name
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version

  # O CRD Application precisa estar estabelecido antes de o argocd-apps tentar
  # criar a Application raiz.
  wait          = true
  wait_for_jobs = true
  timeout       = 900

  values = var.argocd_helm_values

  depends_on = [kubernetes_secret_v1.gitops_repo]
}

# A Application raiz vai pelo chart argocd-apps, e não por kubernetes_manifest,
# pelo mesmo motivo dos charts locais: o CRD Application só existe depois do
# apply acima, e o provider kubernetes valida manifestos durante o plan.
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
              # prune: remover um serviço do Git o remove do cluster.
              prune = true
              # selfHeal: alteração feita direto no cluster é revertida. É o que
              # torna "se não está no código, não existe" verdade operacional.
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
