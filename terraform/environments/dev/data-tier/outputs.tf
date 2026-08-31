output "db_instance_id" {
  value = module.database.db_instance_id
}

output "db_secret_arn" {
  value = module.database.db_secret_arn
}

output "db_secret_name" {
  value = module.database.db_secret_name
}

output "cache_replication_group_id" {
  value = module.cache.cache_replication_group_id
}

output "cache_secret_arn" {
  value = module.cache.cache_secret_arn
}

output "cache_secret_name" {
  value = module.cache.cache_secret_name
}