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
  policy                  = data.aws_iam_policy_document.tfstate_key.json

  tags = { Name = "${var.system}-iac-tfstate" }
}

# Sem policy explícita, o KMS aplica a padrão, que delega TODA a decisão ao IAM
# da conta. Declarar a policy torna o controle visível e versionado.
#
# A primeira declaração é obrigatória: sem delegar ao root da conta, a chave fica
# órfã — nem o administrador consegue alterá-la depois, e a única saída é abrir
# chamado na AWS.
data "aws_iam_policy_document" "tfstate_key" {
  # As três regras abaixo leem "kms:* sobre *" como policy irrestrita. Num
  # documento de KEY POLICY isso não é verdade: o "*" significa "esta chave" —
  # não há outro recurso no escopo. E a declaração de administração pelo root é
  # EXIGIDA pela AWS; sem ela a chave fica órfã, sem ninguém que possa alterá-la.
  #
  # O skip é inline, e não global no .checkov.yaml, para as regras continuarem
  # valendo nas policies IAM de verdade deste repositório (ci-role.tf, irsa.tf).
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

  # O S3 precisa gerar e decifrar a chave de dados a cada leitura e escrita de
  # state. A condição de ViaService restringe o uso ao S3 desta região.
  statement {
    sid    = "PermiteUsoPeloS3"
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
      values   = ["s3.${var.region}.amazonaws.com"]
    }
  }
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

# O versionamento acima guarda uma versão a cada escrita de state — e há uma por
# plan e por apply. Sem expiração, isso cresce para sempre.
#
# 90 dias é folgado de propósito: a versão anterior do state é a rede de
# segurança para recuperar um apply interrompido, e não se descobre que precisa
# dela no mesmo dia.
resource "aws_s3_bucket_lifecycle_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    id     = "expirar-versoes-antigas"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    # Upload de state interrompido deixa partes órfãs que são cobradas e não
    # aparecem na listagem do bucket.
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
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
