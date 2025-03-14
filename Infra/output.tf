output "vpc_id" {
  description = "ID da VPC"
  value       = aws_vpc.poc.id
}

output "public_subnet_ids" {
  description = "IDs das subnets públicas"
  value       = aws_subnet.subnet_publica[*].id
}

output "private_subnet_ids" {
  description = "IDs das subnets privadas"
  value       = aws_subnet.subnet_privada[*].id
}

output "endpoint_redis" {
    description = "Endpoint do redis"
    value       = aws_elasticache_cluster.app_cache.cache_nodes[0].address
}