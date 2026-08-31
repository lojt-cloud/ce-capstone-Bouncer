output "cache_replication_group_id" {
  description = "ElastiCache replication group ID, not the endpoint -- observability's CloudWatch alarm dimension needs this specifically."
  value       = try(aws_elasticache_replication_group.this[0].id, null)
}

output "cache_secret_arn" {
  value = aws_secretsmanager_secret.cache.arn
}

output "cache_secret_name" {
  value = aws_secretsmanager_secret.cache.name
}