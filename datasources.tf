data "aws_vpc" "this" {
  tags = {
    marker = var.marker
  }
}

data "aws_subnet_ids" "public" {
  vpc_id = data.aws_vpc.this.id

  tags = {
    type = "public"
  }
}

data "aws_subnet_ids" "private" {
  vpc_id = data.aws_vpc.this.id

  tags = {
    type = "private"
  }
}

data "aws_route_table" "public" {
  count     = length(data.aws_subnet_ids.public.ids)
  subnet_id = element(sort(tolist(data.aws_subnet_ids.public.ids)), count.index)
}

data "aws_route_table" "private" {
  count     = length(data.aws_subnet_ids.private.ids)
  subnet_id = element(sort(tolist(data.aws_subnet_ids.private.ids)), count.index)
}

data "aws_subnet" "public" {
  count = length(data.aws_subnet_ids.public.ids)
  id    = element(sort(tolist(data.aws_subnet_ids.public.ids)), count.index)
}

data "aws_subnet" "private" {
  count = length(data.aws_subnet_ids.private.ids)
  id    = element(sort(tolist(data.aws_subnet_ids.private.ids)), count.index)
}
