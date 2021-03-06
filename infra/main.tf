variable "key_name" {}
variable "vpc_id" {}
variable "master_eni" {}
variable "slave_eni" {}

data "aws_vpc" "existing" {
    id = "${var.vpc_id}"
}

variable "primary_subnet" {}

provider "aws" {
    version = "1.14.1"
}

