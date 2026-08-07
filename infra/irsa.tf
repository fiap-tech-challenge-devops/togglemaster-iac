
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
  service_accounts = ["*"]

  inline_policies      = { app = data.aws_iam_policy_document.apps.json }
  create_ssm_parameter = true
  ssm_parameter_name   = "/${var.system}/iac/irsa/apps-role-arn"

  tags = local.tags
}

data "aws_iam_policy_document" "eso" {
  statement {
    sid    = "LerSegredosDoSistema"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
      "secretsmanager:ListSecretVersionIds",
    ]
    resources = ["arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:${var.system}/*"]
  }

  statement {
    sid       = "DecifrarComAChaveDoSistema"
    effect    = "Allow"
    actions   = ["kms:Decrypt", "kms:DescribeKey"]
    resources = [aws_kms_key.app_secrets.arn]
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
