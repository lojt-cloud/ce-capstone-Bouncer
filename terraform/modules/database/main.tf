resource "random_password" "master" {
  length  = 32
  special = false # avoids punctuation that some drivers/connection strings choke on; 32 alnum chars is plenty of entropy
}

resource "aws_db_subnet_group" "this" {
  name       = "${var.project}-${var.environment}-db"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name = "${var.project}-${var.environment}-db-subnet-group"
  }
}

resource "aws_db_instance" "this" {
  count = var.enable_billable_resources ? 1 : 0

  identifier     = "${var.project}-${var.environment}-db"
  engine         = "postgres"
  engine_version = var.engine_version

  instance_class    = var.instance_class
  allocated_storage = var.allocated_storage
  storage_type      = var.storage_type
  storage_encrypted = true

  db_name  = var.db_name
  username = var.master_username
  password = random_password.master.result

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.db_security_group_id]

  multi_az            = false # locked decision, see 00-shared-context.md -- cost trade-off, Multi-AZ documented as the prod recommendation
  publicly_accessible = false

  backup_retention_period    = var.backup_retention_days
  auto_minor_version_upgrade = true

  # Deliberate: this is demo data, not data of record. See COSTS.md for the
  # toggle/data-loss trade-off this implies.
  skip_final_snapshot = true
  deletion_protection = false

  copy_tags_to_snapshot           = true
  enabled_cloudwatch_logs_exports = ["postgresql"]

  tags = {
    Name = "${var.project}-${var.environment}-db"

  }
}

resource "aws_secretsmanager_secret" "db" {
  # Not gated by enable_billable_resources: negligible cost (~$0.40/mo), and
  # re-creating a just-deleted secret hits Secrets Manager's recovery-window
  # restriction -- would break the toggle-back-on flow.
  name        = "${var.project}-${var.environment}-db-credentials"
  description = "RDS PostgreSQL master credentials for ${var.project}-${var.environment}. Written by Terraform, read by the app at boot."

  tags = {
    Name = "${var.project}-${var.environment}-db-credentials"
  }
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    username = var.master_username
    password = random_password.master.result
    engine   = "postgres"
    host     = try(aws_db_instance.this[0].address, "")
    port     = try(aws_db_instance.this[0].port, 5432)
    dbname   = var.db_name
  })
}