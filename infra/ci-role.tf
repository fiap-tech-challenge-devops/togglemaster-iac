# Role assumida pelas esteiras dos cinco microsserviços para publicar imagens no
# ECR. Federada pelo mesmo OIDC provider criado no stage bootstrap.
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

data "aws_iam_policy_document" "ci_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Um StringLike por repositório, em vez de um curinga sobre a organização:
    # um repositório novo na org não ganha permissão de push por acidente.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [for s in local.services : "repo:${var.github_org}/${s}:*"]
    }
  }
}

data "aws_iam_policy_document" "ci_ecr" {
  # GetAuthorizationToken não aceita escopo por recurso — é o token do registry
  # inteiro, e a API rejeita qualquer Resource diferente de "*".
  statement {
    sid       = "LoginNoRegistry"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # O push em si fica restrito aos cinco repositórios criados por este stage.
  statement {
    sid    = "PushNosRepositoriosDoSistema"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:DescribeImages",
      "ecr:DescribeRepositories",
    ]
    resources = values(module.ecr.repository_arns)
  }
}

resource "aws_iam_role" "ci" {
  name               = var.ci_role_name
  description        = "Role OIDC das esteiras dos microsserviços para publicar no ECR"
  assume_role_policy = data.aws_iam_policy_document.ci_assume.json

  tags = merge(local.tags, { Name = var.ci_role_name })
}

resource "aws_iam_role_policy" "ci_ecr" {
  name   = "ecr-push"
  role   = aws_iam_role.ci.id
  policy = data.aws_iam_policy_document.ci_ecr.json
}
