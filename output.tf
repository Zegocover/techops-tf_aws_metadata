output "vpc_id" {
  value = data.aws_vpc.this.id
}

output "vpc_cidr" {
  value = data.aws_vpc.this.cidr_block
}

output "vpc_public_subnets_ids" {
  value = sort(data.aws_subnet_ids.public.ids)
}

output "vpc_private_subnets_ids" {
  value = sort(data.aws_subnet_ids.private.ids)
}

output "vpc_public_route_table_ids" {
  description = "List of IDs of public route tables"
  value       = sort(distinct(data.aws_route_table.public.*.id))
}

output "vpc_private_route_table_ids" {
  description = "List of IDs of private route tables"
  value       = sort(distinct(data.aws_route_table.private.*.id))
}

output "vpc_public_subnets" {
  description = "List of public subnets"
  value       = sort(distinct(data.aws_subnet.public.*.id))
}

output "vpc_private_subnets" {
  description = "List of private subnets"
  value       = sort(distinct(data.aws_subnet.private.*.id))
}

output "vpn_cidr" {
  description = "IP range used by VPN"
  value       = lookup(data.aws_vpc.this.tags, "vpn_cidr", "")
}
