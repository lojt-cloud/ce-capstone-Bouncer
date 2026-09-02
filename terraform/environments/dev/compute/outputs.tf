output "app_artifact_bucket_name" {
  value = module.compute.app_artifact_bucket_name
}

output "app_log_group_name" {
  value = module.compute.app_log_group_name
}

output "asg_name" {
  value = module.compute.asg_name
}

output "alb_dns_name" {
  value = module.compute.alb_dns_name
}

output "alb_arn" {
  value = module.compute.alb_arn
}

output "alb_zone_id" {
  value = module.compute.alb_zone_id
}

output "target_group_arn" {
  value = module.compute.target_group_arn
}