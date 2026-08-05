provider "aws" {
  region = var.aws_region
}

# ─── Networking ──────────────────────────────────────────────────────────────
module "networking" {
  source = "./modules/networking"

  project_name         = var.project_name
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
}

# ─── ECR ─────────────────────────────────────────────────────────────────────
module "ecr" {
  source = "./modules/ecr"

  project_name     = var.project_name
  repository_names = var.ecr_repository_names
}

# ─── Databases (RDS, ElastiCache, DynamoDB) ───────────────────────────────────
module "databases" {
  source = "./modules/databases"

  project_name        = var.project_name
  environment         = var.environment
  vpc_id              = module.networking.vpc_id
  vpc_cidr            = var.vpc_cidr
  private_subnet_ids  = module.networking.private_subnet_ids
  db_password         = var.db_password
  db_instance_class   = var.db_instance_class
  cache_node_type     = var.cache_node_type
  dynamodb_table_name = var.dynamodb_table_name
}

# ─── Mensageria (SQS) ─────────────────────────────────────────────────────────
module "messaging" {
  source = "./modules/messaging"

  project_name = var.project_name
  environment  = var.environment
}

# ─── EKS ─────────────────────────────────────────────────────────────────────
module "eks" {
  source = "./modules/eks"

  project_name       = var.project_name
  environment        = var.environment
  vpc_id             = module.networking.vpc_id
  private_subnet_ids = module.networking.private_subnet_ids
  public_subnet_ids  = module.networking.public_subnet_ids
  node_instance_type = var.node_instance_type
  node_desired_size  = var.node_desired_size
  node_min_size      = var.node_min_size
  node_max_size      = var.node_max_size
}

# ─── ArgoCD (instalação via Helm + App of Apps) ───────────────────────────────
# Requer que o cluster EKS já exista (execute terraform apply em dois passos
# na primeira vez — veja terraform/providers.tf para instruções).
module "argocd" {
  source = "./modules/argocd"

  cluster_name           = module.eks.cluster_name
  aws_region             = var.aws_region
  cluster_endpoint       = module.eks.cluster_endpoint
  cluster_ca_certificate = module.eks.cluster_certificate_authority
  gitops_repo_url        = var.gitops_repo_url
  gitops_target_revision = var.gitops_target_revision

  depends_on = [module.eks]
}
