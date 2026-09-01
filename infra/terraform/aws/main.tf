# ============================================================================
# Cloud-Native Platform - AWS Infrastructure
# All AWS-native services: EKS, ECR, RDS PostgreSQL, Secrets Manager, CloudWatch
# ============================================================================

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name_prefix = "cp-${var.environment}"
  azs         = slice(data.aws_availability_zones.available.names, 0, 2)
  common_tags = merge(var.tags, {
    Environment = var.environment
  })
}

# -----------------------------------------------------------------------
# VPC, subnets, and routing
# -----------------------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, {
    Name = "vpc-${local.name_prefix}"
  })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "igw-${local.name_prefix}"
  })
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.${count.index}.0/24"
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name                     = "subnet-public-${local.name_prefix}-${count.index}"
    "kubernetes.io/role/elb" = "1"
  })
}

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${count.index + 10}.0/24"
  availability_zone = local.azs[count.index]

  tags = merge(local.common_tags, {
    Name                              = "subnet-private-${local.name_prefix}-${count.index}"
    "kubernetes.io/role/internal-elb" = "1"
  })
}

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "eip-nat-${local.name_prefix}"
  })
}

# Single NAT gateway shared by both private subnets to control cost
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = merge(local.common_tags, {
    Name = "nat-${local.name_prefix}"
  })

  depends_on = [aws_internet_gateway.main]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(local.common_tags, {
    Name = "rt-public-${local.name_prefix}"
  })
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = merge(local.common_tags, {
    Name = "rt-private-${local.name_prefix}"
  })
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# -----------------------------------------------------------------------
# ECR repositories
# -----------------------------------------------------------------------
resource "aws_ecr_repository" "api" {
  name                 = "cloud-platform-api"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = local.common_tags
}

resource "aws_ecr_repository" "frontend" {
  name                 = "cloud-platform-frontend"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = local.common_tags
}

# -----------------------------------------------------------------------
# EKS cluster
# -----------------------------------------------------------------------
resource "aws_iam_role" "eks_cluster" {
  name = "role-${local.name_prefix}-eks-cluster"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_eks_cluster" "main" {
  name     = "eks-${local.name_prefix}"
  role_arn = aws_iam_role.eks_cluster.arn
  version  = "1.29"

  vpc_config {
    subnet_ids              = concat(aws_subnet.public[*].id, aws_subnet.private[*].id)
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  tags = local.common_tags

  depends_on = [aws_iam_role_policy_attachment.eks_cluster_policy]
}

# OIDC provider for IRSA (IAM Roles for Service Accounts)
data "tls_certificate" "eks_oidc" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks_oidc.certificates[0].sha1_fingerprint]

  tags = local.common_tags
}

# -----------------------------------------------------------------------
# EKS managed node group
# -----------------------------------------------------------------------
resource "aws_iam_role" "eks_node" {
  name = "role-${local.name_prefix}-eks-node"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "eks_node_worker_policy" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_node_cni_policy" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "eks_node_ecr_readonly" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "ng-${local.name_prefix}"
  node_role_arn   = aws_iam_role.eks_node.arn
  subnet_ids      = aws_subnet.private[*].id
  instance_types  = [var.eks_node_instance_type]

  scaling_config {
    min_size     = var.eks_node_min_count
    desired_size = var.eks_node_desired_count
    max_size     = var.eks_node_max_count
  }

  update_config {
    max_unavailable = 1
  }

  tags = local.common_tags

  depends_on = [
    aws_iam_role_policy_attachment.eks_node_worker_policy,
    aws_iam_role_policy_attachment.eks_node_cni_policy,
    aws_iam_role_policy_attachment.eks_node_ecr_readonly,
  ]
}

# Security group AWS creates for the node group, used to scope RDS access
data "aws_security_group" "eks_node" {
  filter {
    name   = "tag:aws:eks:cluster-name"
    values = [aws_eks_cluster.main.name]
  }

  filter {
    name   = "group-name"
    values = ["eks-cluster-sg-${aws_eks_cluster.main.name}-*"]
  }

  depends_on = [aws_eks_node_group.main]
}

# -----------------------------------------------------------------------
# RDS PostgreSQL
# -----------------------------------------------------------------------
resource "aws_db_subnet_group" "main" {
  name       = "dbsubnet-${local.name_prefix}"
  subnet_ids = aws_subnet.private[*].id

  tags = local.common_tags
}

resource "aws_security_group" "rds" {
  name        = "sg-${local.name_prefix}-rds"
  description = "Allow PostgreSQL access from EKS worker nodes"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL from EKS nodes"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [data.aws_security_group.eks_node.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "sg-${local.name_prefix}-rds"
  })
}

resource "aws_db_instance" "main" {
  identifier     = "psql-${local.name_prefix}"
  engine         = "postgres"
  engine_version = "16"

  instance_class         = var.db_instance_class
  allocated_storage      = var.db_allocated_storage
  storage_encrypted      = true
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  db_name  = "cloudplatform"
  username = var.db_admin_username
  password = var.db_admin_password

  backup_retention_period = var.environment == "prod" ? 35 : 7
  multi_az                = var.environment == "prod"
  publicly_accessible     = false
  skip_final_snapshot     = var.environment != "prod"
  deletion_protection     = var.environment == "prod"

  tags = local.common_tags
}

# -----------------------------------------------------------------------
# Secrets Manager
# -----------------------------------------------------------------------
resource "aws_secretsmanager_secret" "db_password" {
  name = "${local.name_prefix}/db-password"
  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = var.db_admin_password
}

resource "aws_secretsmanager_secret" "db_connection_string" {
  name = "${local.name_prefix}/db-connection-string"
  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "db_connection_string" {
  secret_id     = aws_secretsmanager_secret.db_connection_string.id
  secret_string = "postgresql://${var.db_admin_username}:${var.db_admin_password}@${aws_db_instance.main.address}:5432/${aws_db_instance.main.db_name}?sslmode=require"
}

resource "aws_secretsmanager_secret" "db_host" {
  name = "${local.name_prefix}/db-host"
  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "db_host" {
  secret_id     = aws_secretsmanager_secret.db_host.id
  secret_string = aws_db_instance.main.address
}

resource "aws_secretsmanager_secret" "db_user" {
  name = "${local.name_prefix}/db-user"
  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "db_user" {
  secret_id     = aws_secretsmanager_secret.db_user.id
  secret_string = var.db_admin_username
}

# -----------------------------------------------------------------------
# IRSA role for the application ServiceAccount that mounts the CSI secrets.
# The subject below must match the ServiceAccount produced by the k8s/aws
# overlay: name "aws-cloud-platform" (base name "cloud-platform" plus the
# overlay namePrefix) in namespace "cloud-platform-aws".
# -----------------------------------------------------------------------
resource "aws_iam_role" "secrets_access" {
  name = "role-${local.name_prefix}-secrets-access"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:cloud-platform-aws:aws-cloud-platform"
          "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_policy" "secrets_access" {
  name = "policy-${local.name_prefix}-secrets-access"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["secretsmanager:GetSecretValue"]
      Resource = [
        aws_secretsmanager_secret.db_password.arn,
        aws_secretsmanager_secret.db_connection_string.arn,
        aws_secretsmanager_secret.db_host.arn,
        aws_secretsmanager_secret.db_user.arn,
      ]
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "secrets_access" {
  role       = aws_iam_role.secrets_access.name
  policy_arn = aws_iam_policy.secrets_access.arn
}

# -----------------------------------------------------------------------
# CloudWatch logging and alarms
# -----------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "eks" {
  name              = "/aws/eks/${local.name_prefix}/cluster"
  retention_in_days = var.environment == "prod" ? 90 : 30

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "node_cpu" {
  alarm_name          = "alarm-${local.name_prefix}-high-cpu"
  alarm_description   = "Alert when node CPU exceeds 80%"
  namespace           = "ContainerInsights"
  metric_name         = "node_cpu_utilization"
  statistic           = "Average"
  comparison_operator = "GreaterThanThreshold"
  threshold           = 80
  period              = 300
  evaluation_periods  = 3

  dimensions = {
    ClusterName = aws_eks_cluster.main.name
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "node_memory" {
  alarm_name          = "alarm-${local.name_prefix}-high-memory"
  alarm_description   = "Alert when node memory exceeds 80%"
  namespace           = "ContainerInsights"
  metric_name         = "node_memory_utilization"
  statistic           = "Average"
  comparison_operator = "GreaterThanThreshold"
  threshold           = 80
  period              = 300
  evaluation_periods  = 3

  dimensions = {
    ClusterName = aws_eks_cluster.main.name
  }

  tags = local.common_tags
}
