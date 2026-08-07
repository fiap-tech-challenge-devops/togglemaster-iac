# ── Chave dos segredos de aplicação ───────────────────────────────────────────
# Uma chave para os cinco segredos (3 do RDS + 2 de aplicação), e não a padrão do
# Secrets Manager.
#
# Com a chave gerenciada pela AWS, qualquer principal com permissão de
# secretsmanager na conta lê o conteúdo. Com chave própria, o acesso passa também
# pela key policy e cada uso aparece no CloudTrail com o ARN de quem leu.
#
# Uma chave só, e não uma por segredo: KMS cobra por chave por mês, e todos aqui
# pertencem ao mesmo sistema — não há isolamento a ganhar em separá-las.
resource "aws_kms_key" "app_secrets" {
  description             = "Criptografia dos segredos de aplicação do ${var.system}"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.app_secrets_key.json

  tags = merge(local.tags, { Name = "${var.system}-app-secrets" })
}

data "aws_iam_policy_document" "app_secrets_key" {
  # Mesmo raciocínio da chave do state, em bootstrap/main.tf: num documento de
  # key policy o "*" é a própria chave, e a delegação ao root é exigida pela AWS.
  #checkov:skip=CKV_AWS_111:Key policy — o "*" é a própria chave, e a delegação ao root é exigida pela AWS
  #checkov:skip=CKV_AWS_356:Key policy — Resource "*" num documento de chave significa a própria chave
  #checkov:skip=CKV_AWS_109:Key policy — kms:* para o root é o que impede a chave de ficar órfã

  statement {
    sid       = "PermiteAdministracaoPelaConta"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  # O Secrets Manager cifra e decifra o conteúdo do segredo em nome de quem
  # chama. A condição de ViaService restringe esse uso ao serviço, nesta região.
  statement {
    sid    = "PermiteUsoPeloSecretsManager"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey",
      "kms:DescribeKey",
    ]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["secretsmanager.${var.region}.amazonaws.com"]
    }
  }

  # O External Secrets Operator decifra direto, e não via Secrets Manager — a
  # condição acima não o cobre. Sem esta declaração, o ExternalSecret fica preso
  # em SecretSyncedError com AccessDenied citando o KMS.
  statement {
    sid       = "PermiteLeituraPeloExternalSecrets"
    effect    = "Allow"
    actions   = ["kms:Decrypt", "kms:DescribeKey"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = [module.irsa_eso.role_arn]
    }
  }
}

resource "aws_kms_alias" "app_secrets" {
  name          = "alias/${var.system}-app-secrets"
  target_key_id = aws_kms_key.app_secrets.key_id
}

# ── Senhas dos RDS ────────────────────────────────────────────────────────────
# Geradas pelo Terraform, o que significa que ficam no tfstate. É o motivo de o
# bucket de state ter versionamento, criptografia e bloqueio público.
resource "random_password" "rds" {
  for_each = local.rds_instances

  length  = 24
  special = true

  # Restringe os especiais aos que sobrevivem à connection string mesmo depois do
  # urlencode — barra e arroba quebrariam o parsing da URL.
  override_special = "!#$%&*-_=+?"
}

# ── Connection strings no Secrets Manager ─────────────────────────────────────
# Nome previsível (<system>/rds/<serviço>) porque o ExternalSecret no repositório
# GitOps referencia essa string. Mudar o padrão aqui quebra o deploy lá.
module "rds_secret" {
  source   = "github.com/fiap-tech-challenge-devops/terraform-aws-modules//secrets-manager?ref=v0.1.0"
  for_each = local.rds_instances

  name        = "${var.system}/rds/${each.key}"
  description = "Credenciais do RDS de ${each.key}"

  secret_key_value = {
    engine            = "postgres"
    host              = module.rds[each.key].db_instance_address
    port              = "5432"
    database          = each.value.db_name
    username          = each.value.username
    password          = random_password.rds[each.key].result
    connection_string = "postgres://${each.value.username}:${urlencode(random_password.rds[each.key].result)}@${module.rds[each.key].db_instance_address}:5432/${each.value.db_name}?sslmode=require"
  }

  recovery_window_in_days = 0 # ambiente de lab: exclusão imediata permite recriar com o mesmo nome
  kms_key_arn             = aws_kms_key.app_secrets.arn

  tags = local.tags
}

# ── Segredos de aplicação ─────────────────────────────────────────────────────

# Chave-raiz do auth-service, que protege o endpoint /admin/keys.
resource "random_password" "master_key" {
  length  = 32
  special = false # alfanumérica: vai em header Authorization, sem escaping
}

resource "aws_secretsmanager_secret" "app_auth" {
  name                    = "${var.system}/app/auth"
  description             = "MASTER_KEY do auth-service"
  recovery_window_in_days = 0
  kms_key_id              = aws_kms_key.app_secrets.arn

  tags = local.tags
}

resource "aws_secretsmanager_secret_version" "app_auth" {
  secret_id     = aws_secretsmanager_secret.app_auth.id
  secret_string = jsonencode({ MASTER_KEY = random_password.master_key.result })
}

# SERVICE_API_KEY do evaluation-service. O segredo é criado aqui apenas para
# EXISTIR — o valor real é emitido pelo auth-service depois que o cluster está de
# pé. Sem ignore_changes, cada apply reverteria a chave para o placeholder.
resource "aws_secretsmanager_secret" "app_evaluation" {
  name                    = "${var.system}/app/evaluation"
  description             = "SERVICE_API_KEY do evaluation-service (valor emitido fora do Terraform)"
  recovery_window_in_days = 0
  kms_key_id              = aws_kms_key.app_secrets.arn

  tags = local.tags
}

resource "aws_secretsmanager_secret_version" "app_evaluation" {
  secret_id     = aws_secretsmanager_secret.app_evaluation.id
  secret_string = jsonencode({ SERVICE_API_KEY = "placeholder" })

  lifecycle {
    ignore_changes = [secret_string]
  }
}
