data "aws_vpc" "this" {
  tags = {
    Name = var.marker
  }
}

data "aws_route_table" "public" {
  count     = length(local.public_subnet_ids)
  subnet_id = element(local.public_subnet_ids, count.index)
}

data "aws_route_table" "private" {
  count     = length(local.private_subnet_ids)
  subnet_id = element(local.private_subnet_ids, count.index)
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.this.id]
  }

  tags = {
    type = "public"
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.this.id]
  }

  tags = {
    type = "private"
  }
}