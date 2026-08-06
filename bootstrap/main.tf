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
