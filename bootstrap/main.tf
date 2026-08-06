data "aws_caller_identity" "current" {}

locals {
  bucket_name = "${var.system}-iac-tfstate-${data.aws_caller_identity.current.account_id}"
}

# ── Bucket do state remoto ────────────────────────────────────────────────────
# Único recurso deste stage. A identidade que as esteiras usam (OIDC provider e
# IAM role) NÃO é criada aqui, de propósito: seria circular — a esteira precisaria
# assumir a role para poder criar a própria role. Ver README, "Pré-requisitos".
#
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

# Chave própria, e não a gerenciada pela AWS (AES256).
#
# O state contém as senhas dos três RDS e o conteúdo do Secrets Manager em texto
# claro. Com chave própria, todo acesso ao conteúdo aparece no CloudTrail e pode
# ser restrito pela key policy — nada disso existe com a chave padrão do S3.
resource "aws_kms_key" "tfstate" {
  description             = "Criptografia do state remoto do ${var.system}"
  enable_key_rotation     = true
  deletion_window_in_days = 30

  tags = { Name = "${var.system}-iac-tfstate" }
}

resource "aws_kms_alias" "tfstate" {
  name          = "alias/${var.system}-iac-tfstate"
  target_key_id = aws_kms_key.tfstate.key_id
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.tfstate.arn
    }

    # Sem isto, cada objeto gera uma chamada à API do KMS. O state é lido e
    # gravado a cada plan e apply — a bucket key reduz isso a uma chamada por
    # período, cortando custo e risco de throttling.
    bucket_key_enabled = true
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
