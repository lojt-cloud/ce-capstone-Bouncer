resource "aws_lb" "app" {
  count = var.enable_billable_resources ? 1 : 0

  name               = "${var.project}-${var.environment}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_security_group_id]
  subnets            = var.public_subnet_ids

  drop_invalid_header_fields = true

  # Deliberately off -- this ALB is meant to be destroyed/recreated via the
  # enable_billable_resources toggle; deletion protection would block that.
  enable_deletion_protection = false
}

resource "aws_lb_target_group" "app" {
  count = var.enable_billable_resources ? 1 : 0

  name        = "${var.project}-${var.environment}-app-tg"
  port        = var.app_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    path                = var.health_check_path
    protocol            = "HTTP"
    matcher             = "200"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 15
    timeout             = 5
  }

  deregistration_delay = 30
}

resource "aws_lb_listener" "http" {
  count = var.enable_billable_resources ? 1 : 0

  load_balancer_arn = aws_lb.app[0].arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app[0].arn
  }
}