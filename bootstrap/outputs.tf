output "state_bucket" {
  description = "Bucket S3 do state remoto. Use em -backend-config=bucket=..."
  value       = aws_s3_bucket.tfstate.id
}

output "backend_config_hint" {
  description = "Argumentos de -backend-config usados pelos stages infra e addons."
  value       = "-backend-config=bucket=${aws_s3_bucket.tfstate.id} -backend-config=region=${var.region} -backend-config=use_lockfile=true"
}
