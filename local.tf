locals {

  private_subnet_ids = sort(data.aws_subnets.private.ids)
  public_subnet_ids  = sort(data.aws_subnets.public.ids)

}