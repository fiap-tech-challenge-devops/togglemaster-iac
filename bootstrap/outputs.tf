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
