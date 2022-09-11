provider "aws" {
  source = "hashicorp/aws"
  region  = "${var.region}"
  profile = "infra-provisioning"
  assume_role = {
    role_arn = "${var.workspace_iam_roles[terraform.workspace]}"
  }
}
