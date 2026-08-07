data "aws_caller_identity" "current" {}

locals {
  cluster_name = "eks-${var.system}"

  tags = {
    System = var.system
  }

  rds_instances = {
    auth      = { db_name = "auth_db", username = "auth_user" }
    flags     = { db_name = "flags_db", username = "flags_user" }
    targeting = { db_name = "targeting_db", username = "targeting_user" }
  }

  services = [
    "auth-service",
    "flag-service",
    "targeting-service",
    "evaluation-service",
    "analytics-service",
  ]
}

module "vpc" {
  source = "github.com/fiap-tech-challenge-devops/terraform-aws-modules//vpc?ref=v0.1.0"

  name       = var.system
  cidr_block = var.vpc_cidr

  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs

  enable_nat_gateway = true
  single_nat_gateway = true

  public_subnet_tags = {
    "kubernetes.io/role/elb"                      = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"             = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "karpenter.sh/discovery"                      = local.cluster_name
  }

  tags = local.tags
}

module "eks" {
  source = "github.com/fiap-tech-challenge-devops/terraform-aws-modules//eks?ref=v0.1.0"

  cluster_name    = local.cluster_name
  cluster_version = var.cluster_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  endpoint_private_access = true
  endpoint_public_access  = true

  enable_irsa    = true
  create_kms_key = true

  bootstrap_cluster_creator_admin_permissions = true

  node_groups = {
    baseline = {
      instance_types = var.node_instance_types
      capacity_type  = "ON_DEMAND"
      desired_size   = var.node_desired_size
      min_size       = var.node_min_size
      max_size       = var.node_max_size
      labels = {
        role = "baseline"
      }
    }
  }

  cluster_addons = {
    coredns    = {}
    kube-proxy = {}
    vpc-cni = {
      configuration_values = jsonencode({
        env = {
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
      })
    }
    eks-pod-identity-agent = {}
  }

  enable_ebs_csi_driver = false

  access_entries = {
    for arn in var.admin_iam_arns : replace(arn, "/[^a-zA-Z0-9]/", "-") => {
      principal_arn = arn
      type          = "STANDARD"
      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          scope_type = "cluster"
        }
      }
    }
  }

  tags = local.tags
}

module "karpenter" {
  source = "github.com/fiap-tech-challenge-devops/terraform-aws-modules//eks-karpenter?ref=v0.1.0"

  cluster_name      = module.eks.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  region            = var.region

  create_ssm_parameters = true
  ssm_parameter_prefix  = "/${var.system}/iac/karpenter"

  tags = local.tags
}

module "lb_controller" {
  source = "github.com/fiap-tech-challenge-devops/terraform-aws-modules//eks-aws-lb-controller?ref=v0.1.0"

  cluster_name      = module.eks.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  vpc_id            = module.vpc.vpc_id
  region            = var.region

  create_ssm_parameters = true
  ssm_parameter_prefix  = "/${var.system}/iac/lb-controller"

  tags = local.tags
}

module "rds" {
  source   = "github.com/fiap-tech-challenge-devops/terraform-aws-modules//rds?ref=v0.1.0"
  for_each = local.rds_instances

  name                = "rds-${var.system}-${each.key}"
  security_group_name = "rds-sg-${var.system}-${each.key}"

  engine         = "postgres"
  engine_version = var.rds_engine_version
  instance_class = var.rds_instance_class

  allocated_storage = var.rds_allocated_storage
  storage_type      = "gp3"

  db_name  = each.value.db_name
  username = each.value.username

  manage_master_user_password = false
  password                    = random_password.rds[each.key].result

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  allowed_cidr_blocks = [var.vpc_cidr]

  multi_az                = false
  backup_retention_period = 0
  deletion_protection     = false
  skip_final_snapshot     = true

  tags = local.tags
}

module "redis" {
  source = "github.com/fiap-tech-challenge-devops/terraform-aws-modules//elasticache?ref=v0.1.0"

  name                = "redis-${var.system}"
  security_group_name = "redis-sg-${var.system}"

  engine         = "redis"
  engine_version = var.redis_engine_version
  node_type      = var.redis_node_type

  num_cache_clusters = 1

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  allowed_cidr_blocks = [var.vpc_cidr]

  at_rest_encryption_enabled = true
  transit_encryption_enabled = false
  snapshot_retention_limit   = 0

  tags = local.tags
}

module "sqs" {
  source = "github.com/fiap-tech-challenge-devops/terraform-aws-modules//sqs?ref=v0.1.0"

  name                      = "${var.system}-evaluation-events"
  receive_wait_time_seconds = 20

  create_dlq = false

  tags = local.tags
}

module "dynamodb" {
  source = "github.com/fiap-tech-challenge-devops/terraform-aws-modules//dynamodb?ref=v0.1.0"

  name         = "ToggleMasterAnalytics"
  hash_key     = "event_id"
  billing_mode = "PAY_PER_REQUEST"

  attributes = [
    { name = "event_id", type = "S" }
  ]

  tags = local.tags
}

module "ecr" {
  source = "github.com/fiap-tech-challenge-devops/terraform-aws-modules//ecr?ref=v0.1.0"

  namespace        = var.system
  repository_names = local.services

  image_tag_mutability = "IMMUTABLE"
  scan_on_push         = true

  untagged_image_expiration_days = 7
  max_tagged_images              = 30

  create_ssm_parameters = true
  ssm_parameter_prefix  = "/${var.system}/iac/ecr"

  tags = local.tags
}
