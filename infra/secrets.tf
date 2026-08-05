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
  source   = "${local.modules}//secrets-manager?ref=${var.module_ref}"
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

  tags = local.tags
}

resource "aws_secretsmanager_secret_version" "app_evaluation" {
  secret_id     = aws_secretsmanager_secret.app_evaluation.id
  secret_string = jsonencode({ SERVICE_API_KEY = "placeholder" })

  lifecycle {
    ignore_changes = [secret_string]
  }
}
