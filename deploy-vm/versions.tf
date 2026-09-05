terraform {
  required_version = ">= 1.5.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.62"
    }
  }

  # Optional remote state (uncomment and configure when ready):
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "deploy-vm/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "your-terraform-locks"
  #   encrypt        = true
  # }
}
