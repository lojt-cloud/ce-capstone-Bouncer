resource "random_password" "auth_token" {
  length  = 32
  special = false # Redis AUTH tokens can't contain '/', '"', or '@' -- alnum-only sidesteps that entirely
}

resource "aws_elasticache_subnet_group" "this" {
  name       = "${var.project}-${var.environment}-cache"
  subnet_ids = var.private_subnet_ids
}

resource "aws_elasticache_replication_group" "this" {
  count = var.enable_billable_resources ? 1 : 0

  replication_group_id = "${var.project}-${var.environment}-cache"
  description          = "Shared Redis for login lockout counters and session storage -- ${var.project}-${var.environment}"

  engine         = "redis"
  engine_version = var.engine_version
  node_type      = var.node_type

  num_cache_clusters         = 1
  automatic_failover_enabled = false
  multi_az_enabled           = false

  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = [var.cache_security_group_id]

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  transit_encryption_mode    = "required"
  auth_token                 = random_password.auth_token.result

  tags = {
    Name = "${var.project}-${var.environment}-cache"
  }
}

resource "aws_secretsmanager_secret" "cache" {
  name        = "${var.project}-${var.environment}-cache-credentials"
  description = "ElastiCache Redis AUTH token + endpoint for ${var.project}-${var.environment}. Written by Terraform, read by the app at boot."

  tags = {
    Name = "${var.project}-${var.environment}-cache-credentials"
  }
}

resource "aws_secretsmanager_secret_version" "cache" {
  secret_id = aws_secretsmanager_secret.cache.id
  secret_string = jsonencode({
    auth_token = random_password.auth_token.result
    host       = try(aws_elasticache_replication_group.this[0].primary_endpoint_address, "")
    port       = try(aws_elasticache_replication_group.this[0].port, 6379)
  })
}