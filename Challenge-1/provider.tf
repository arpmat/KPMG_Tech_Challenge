provider "aws" {
  source = "hashicorp/aws"
  region  = "${var.region}"
  profile = "infra-provisioning"
}
