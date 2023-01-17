`tf_aws_metadata` module
-----------------------------

This module is used as a metadata _service_ that given VPC marker (name) exposes attributes of that VPC as output resources which can be consumed by other Terraform resources, without having to duplicate the `data_source` logic.

Requirements
------------

Minimum v3.55 of the AWS Provider

Input variables
---------------

 * `marker` - (string) **REQUIRED** - VPC marker / VPC name - used to resolve the VPC resource

Usage
-----

```hcl
module "metadata" {
  source = "github.com/zegocover/techops-tf_aws_metadata"
  marker = "productionvpc"
}

output "private_subnets" {
  value = "${module.metadata.vpc_private_subnets}"
}

```

Outputs
-------

 * `vpc_id`: The ID of the VPC
 * `vpc_cidr`: The CIDR block of the VPC
 * `vpc_public_subnets_ids` - A list of AWS Subnet IDs for all public subnets inside the VPC
 * `vpc_private_subnets_ids` - A list of AWS Subnet IDs for all private subnets inside the VPC
 * `vpc_public_route_table_ids` - A list of all public AWS Route Table IDs
 * `vpc_private_route_table_ids` - A list of all private AWS Route Table IDs
 * `vpc_public_subnets` - A list of CIDR blocks for all public subnets inside the VPC
 * `vpc_private_subnets` - A list of CIDR blocks for all private subnets inside the VPC
