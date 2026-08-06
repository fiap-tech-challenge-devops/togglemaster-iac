# Identidades AWS dos componentes que rodam no cluster. Todas ficam aqui, no
# stage infra, porque IRSA é IAM — plano AWS puro, sem provider de Kubernetes.
# O que consome essas roles (charts e manifests) vive no repositório GitOps.

# ── Microsserviços ────────────────────────────────────────────────────────────
# Uma role por namespace, e não por serviço: o evaluation produz na fila, o
# analytics consome dela e grava no DynamoDB. Separar em duas roles com policies
# assimétricas seria o menor privilégio de fato, e fica registrado como melhoria.
data "aws_iam_policy_document" "apps" {
  statement {
    sid    = "EvaluationProduzAnalyticsConsome"
    effect = "Allow"
    actions = [
      "sqs:SendMessage",
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueUrl",
      "sqs:GetQueueAttributes",
    ]
    resources = [module.sqs.queue_arn]
  }

  statement {
    sid       = "AnalyticsGravaEventos"
    effect    = "Allow"
    actions   = ["dynamodb:PutItem", "dynamodb:GetItem", "dynamodb:DescribeTable"]
    resources = [module.dynamodb.table_arn]
  }
}

module "irsa_apps" {
  source = "github.com/fiap-tech-challenge-devops/terraform-aws-modules//iam-irsa?ref=v0.1.0"

  name              = "role-eks-${var.system}-apps"
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url

  namespace        = var.app_namespace
  service_accounts = ["*"] # qualquer SA do namespace da aplicação

  inline_policies      = { app = data.aws_iam_policy_document.apps.json }
  create_ssm_parameter = true
  ssm_parameter_name   = "/${var.system}/iac/irsa/apps-role-arn"

  tags = local.tags
}

# ── External Secrets Operator ─────────────────────────────────────────────────
# O ESO lê o Secrets Manager e materializa Secrets no cluster. É ele que entrega
# as connection strings dos RDS aos pods.
data "aws_iam_policy_document" "eso" {
  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
      "secretsmanager:ListSecretVersionIds",
    ]
    # Escopado ao prefixo do sistema: o operador não enxerga segredos de outros
    # sistemas que compartilhem a conta.
    resources = ["arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:${var.system}/*"]
  }
}

module "irsa_eso" {
  source = "github.com/fiap-tech-challenge-devops/terraform-aws-modules//iam-irsa?ref=v0.1.0"

  name              = "role-eks-${var.system}-external-secrets"
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url

  namespace        = "external-secrets"
  service_accounts = ["external-secrets"]

  inline_policies      = { secretsmanager = data.aws_iam_policy_document.eso.json }
  create_ssm_parameter = true
  ssm_parameter_name   = "/${var.system}/iac/irsa/external-secrets-role-arn"

  tags = local.tags
}

# ── KEDA ──────────────────────────────────────────────────────────────────────
# O analytics-service escala pela profundidade da fila, não por CPU. Quem consulta
# a fila para decidir a escala é o keda-operator — daí ele precisar da própria
# role, separada da dos pods: só ler o tamanho, nunca consumir mensagem.
data "aws_iam_policy_document" "keda" {
  statement {
    effect    = "Allow"
    actions   = ["sqs:GetQueueAttributes"]
    resources = [module.sqs.queue_arn]
  }
}

module "irsa_keda" {
  source = "github.com/fiap-tech-challenge-devops/terraform-aws-modules//iam-irsa?ref=v0.1.0"

  name              = "role-eks-${var.system}-keda"
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url

  namespace        = "keda"
  service_accounts = ["keda-operator"]

  inline_policies      = { sqs = data.aws_iam_policy_document.keda.json }
  create_ssm_parameter = true
  ssm_parameter_name   = "/${var.system}/iac/irsa/keda-role-arn"

  tags = local.tags
}
