terraform {
	required_version = ">= 1.3.0"

	required_providers {
		aws = {
			source  = "hashicorp/aws"
			version = "~> 5.0"
		}
	}

	backend "remote" {
		organization = "DevOps-Class-7"

		workspaces {
			name = "ChrisBrownDevOps"
		}
	}
}

provider "aws" {
	region = "us-east-1"
}

# Step 2: Create a Terraform Cloud API token in the UI and set it locally as
# the environment variable TF_TOKEN_app_terraform_io before running Terraform.
