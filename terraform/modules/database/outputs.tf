output "db_instance_id" {
  description = "RDS instance identifier (e.g. ce-capstone-bouncer-dev-db) for the CloudWatch DBInstanceIdentifier dimension. Deliberately .identifier, NOT .id -- as of AWS provider 5.x, .id returns the DBI resource ID (db-XXXX), a different value standard AWS/RDS metrics don't use. Confirmed against provider docs + real list-metrics output, 2026-09-02."
  value       = try(aws_db_instance.this[0].identifier, null)
}
output "db_secret_arn" {
  value = aws_secretsmanager_secret.db.arn
}
output "db_secret_name" {
  value = aws_secretsmanager_secret.db.name
}
