data "aws_caller_identity" "current" {}

locals {
  bucket_name = "${var.system}-iac-tfstate-${data.aws_caller_identity.current.account_id}"
}

# ── Bucket do state remoto ────────────────────────────────────────────────────
# O lock é feito por arquivo no próprio bucket (use_lockfile, backend S3), então
# não há tabela DynamoDB: um recurso a menos para criar, pagar e destruir.
resource "aws_s3_bucket" "tfstate" {
  bucket = local.bucket_name

  # Sem force_destroy: o state é o registro do que existe na AWS. Apagar o bucket
  # por engano é pior do que um destroy falhar.
  tags = { Name = local.bucket_name }
}

# Versionamento é o que permite recuperar um state corrompido por apply
# interrompido — é a única rede de segurança que existe aqui.
resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# O state contém as senhas dos RDS em texto claro. Bloqueio público explícito,
# mesmo com o default da conta já sendo restritivo.
resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ── OIDC do GitHub Actions ────────────────────────────────────────────────────
# Federação em vez de access key estática: a esteira troca o token do run por
# credenciais temporárias. Não há segredo de longa duração no repositório.
resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  # A AWS valida o certificado do GitHub pela cadeia de CA desde 2023 e não usa
  # mais esta lista, mas a API ainda exige o campo preenchido.
  thumbprint_list = ["6938fd4d98bab03fa02197ae0fb9c90c26149988"]

  tags = { Name = "github-actions" }
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}

locals {
  github_oidc_arn = var.create_github_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
}

# ── Role das esteiras de IaC ──────────────────────────────────────────────────
data "aws_iam_policy_document" "iac_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Restringe ao repositório de IaC. Sem esta condição, qualquer repositório do
    # GitHub poderia assumir a role.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}/${var.iac_repository}:*"]
    }
  }
}

resource "aws_iam_role" "iac" {
  name               = var.iac_role_name
  description        = "Role OIDC das esteiras de IaC (${var.github_org}/${var.iac_repository})"
  assume_role_policy = data.aws_iam_policy_document.iac_assume.json

  tags = { Name = var.iac_role_name }
}

# AdministratorAccess porque este stage provisiona VPC, EKS, RDS, IAM e ECR — o
# conjunto de permissões mínimo para isso é grande o bastante para se aproximar
# de admin, e mantê-lo correto daria mais trabalho do que segurança neste escopo.
# Em produção, troque por uma policy derivada do que o plan realmente exige.
resource "aws_iam_role_policy_attachment" "iac_admin" {
  role       = aws_iam_role.iac.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
