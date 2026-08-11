output "state_bucket" {
  description = "Bucket S3 do state remoto. Use em -backend-config=bucket=..."
  value       = aws_s3_bucket.tfstate.id
}

output "state_kms_key_arn" {
  description = "ARN da KMS key que criptografa o state. Quem for ler o state precisa de kms:Decrypt nela."
  value       = aws_kms_key.tfstate.arn
}

output "backend_config_hint" {
  description = "Argumentos de -backend-config usados pelos stages infra e addons."
  value       = "-backend-config=bucket=${aws_s3_bucket.tfstate.id} -backend-config=region=${var.region} -backend-config=use_lockfile=true"
}

output "registry_url" {
  description = "URL base do registry — alvo do docker login."
  value       = module.ecr.registry_url
}

output "repository_urls" {
  description = "URL de cada repositório, por serviço. Vai no campo image.repository dos values do GitOps."
  value       = module.ecr.repository_urls
}

output "ci_role_arn" {
  description = "ARN da role de push no ECR. Configure no secret AWS_ROLE_ARN dos repositórios dos microsserviços."
  value       = aws_iam_role.ci.arn
}
