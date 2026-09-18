# cp terraform.tfvars.example terraform.tfvars

region               = "us-east-1"
master_instance_type = "t3.medium"
worker_instance_type = "t3.medium"

# Point at a feature branch while testing changes to the playbook
repo_branch = "feature/terraform"

# aws_profile = "ps-sandbox"
