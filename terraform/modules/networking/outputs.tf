output "vpc_id" {
  value = aws_vpc.this.id
}

output "vpc_cidr" {
  value = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "public_route_table_id" {
  value = aws_route_table.public.id
}

output "availability_zones" {
  value = var.availability_zones
}
output "nat_gateway_id" {
  value = var.enable_billable_resources ? aws_nat_gateway.this[0].id : null
}

output "private_route_table_id" {
  value = aws_route_table.private.id
}
output "flow_log_group_name" {
  value = aws_cloudwatch_log_group.vpc_flow_logs.name
}

output "flow_log_group_arn" {
  value = aws_cloudwatch_log_group.vpc_flow_logs.arn
}