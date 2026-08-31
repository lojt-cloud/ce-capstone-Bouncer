output "db_instance_id" {
  description = "RDS instance identifier, not the endpoint -- observability's CloudWatch alarm dimension needs this specifically."
  value       = try(aws_db_instance.this[0].id, null)
}

output "db_secret_arn" {
  value = aws_secretsmanager_secret.db.arn
}

output "db_secret_name" {
  value = aws_secretsmanager_secret.db.name
}