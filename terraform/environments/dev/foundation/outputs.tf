#VPC Outputs
output "vpc_id" {
  value = module.networking.vpc_id
}

output "vpc_cidr" {
  value = module.networking.vpc_cidr
}


#Subnet Outputs
output "public_subnet_ids" {
  value = module.networking.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.networking.private_subnet_ids
}

#SG IDs
output "alb_security_group_id" {
  value = module.security.alb_security_group_id
}

output "app_security_group_id" {
  value = module.security.app_security_group_id
}

output "db_security_group_id" {
  value = module.security.db_security_group_id
}

output "cache_security_group_id" {
  value = module.security.cache_security_group_id
}

#