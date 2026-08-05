aws_region   = "us-east-1"
project_name = "feature-flags"
environment  = "production"

vpc_cidr             = "10.0.0.0/16"
availability_zones   = ["us-east-1a", "us-east-1b"]
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.10.0/24", "10.0.20.0/24"]

db_instance_class   = "db.t3.micro"
cache_node_type     = "cache.t3.micro"
dynamodb_table_name = "ToggleMasterAnalytics"

node_instance_type = "t3.small"
node_desired_size = 2
node_min_size      = 1
node_max_size      = 4

ecr_repository_names = [
  "pos2/auth-service",
  "pos2/flag-service",
  "pos2/targeting-service",
  "pos2/evaluation-service",
  "pos2/analytics-service",
]

gitops_repo_url        = "https://github.com/jc-perroni/fiap-fase-3.git"
gitops_target_revision = "main"
