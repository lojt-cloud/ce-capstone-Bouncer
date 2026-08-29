resource "aws_security_group" "alb" {
  name        = "${var.name_prefix}-alb-sg"
  description = "ALB: public HTTP/HTTPS in, app tier only out"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-alb-sg"
  }
}

resource "aws_security_group" "app" {
  name        = "${var.name_prefix}-app-sg"
  description = "App tier: only reachable from the ALB, no SSH (SSM-managed)"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-app-sg"
  }
}

resource "aws_security_group" "db" {
  name        = "${var.name_prefix}-db-sg"
  description = "RDS: only reachable from the app tier"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-db-sg"
  }
}

resource "aws_security_group" "cache" {
  name        = "${var.name_prefix}-cache-sg"
  description = "ElastiCache Redis: only reachable from the app tier"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-cache-sg"
  }
}

# --- ALB ---
resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description        = "HTTP from internet"
  from_port          = 80
  to_port             = 80
  ip_protocol        = "tcp"
  cidr_ipv4          = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  description        = "HTTPS from internet"
  from_port          = 443
  to_port             = 443
  ip_protocol        = "tcp"
  cidr_ipv4          = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_app" {
  security_group_id            = aws_security_group.alb.id
  description                   = "To app tier only"
  from_port                     = var.app_port
  to_port                       = var.app_port
  ip_protocol                   = "tcp"
  referenced_security_group_id  = aws_security_group.app.id
}

# --- App ---
resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  security_group_id            = aws_security_group.app.id
  description                   = "App port from ALB only"
  from_port                     = var.app_port
  to_port                       = var.app_port
  ip_protocol                   = "tcp"
  referenced_security_group_id  = aws_security_group.alb.id
}

resource "aws_vpc_security_group_egress_rule" "app_https_out" {
  security_group_id = aws_security_group.app.id
  description         = "HTTPS out (SSM, package installs, external APIs) via NAT"
  from_port           = 443
  to_port              = 443
  ip_protocol         = "tcp"
  cidr_ipv4           = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "app_to_db" {
  security_group_id            = aws_security_group.app.id
  description                   = "To RDS"
  from_port                     = var.db_port
  to_port                       = var.db_port
  ip_protocol                   = "tcp"
  referenced_security_group_id  = aws_security_group.db.id
}

resource "aws_vpc_security_group_egress_rule" "app_to_cache" {
  security_group_id            = aws_security_group.app.id
  description                   = "To ElastiCache Redis"
  from_port                     = var.cache_port
  to_port                       = var.cache_port
  ip_protocol                   = "tcp"
  referenced_security_group_id  = aws_security_group.cache.id
}

# --- DB ---
resource "aws_vpc_security_group_ingress_rule" "db_from_app" {
  security_group_id            = aws_security_group.db.id
  description                   = "DB port from app tier only"
  from_port                     = var.db_port
  to_port                       = var.db_port
  ip_protocol                   = "tcp"
  referenced_security_group_id  = aws_security_group.app.id
}

# --- Cache ---
resource "aws_vpc_security_group_ingress_rule" "cache_from_app" {
  security_group_id            = aws_security_group.cache.id
  description                   = "Redis port from app tier only"
  from_port                     = var.cache_port
  to_port                       = var.cache_port
  ip_protocol                   = "tcp"
  referenced_security_group_id  = aws_security_group.app.id
}