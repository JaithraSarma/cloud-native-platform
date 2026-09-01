variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "cloudplatform"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "eks_node_instance_type" {
  description = "EC2 instance type for EKS managed node group"
  type        = string
  default     = "t3.medium"
}

variable "eks_node_min_count" {
  description = "Minimum node count for the EKS managed node group"
  type        = number
  default     = 2
}

variable "eks_node_desired_count" {
  description = "Desired node count for the EKS managed node group"
  type        = number
  default     = 2
}

variable "eks_node_max_count" {
  description = "Maximum node count for autoscaling"
  type        = number
  default     = 5
}

variable "db_instance_class" {
  description = "Instance class for the RDS PostgreSQL instance"
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "Allocated storage in GB for RDS PostgreSQL"
  type        = number
  default     = 20
}

variable "db_admin_username" {
  description = "PostgreSQL admin username"
  type        = string
  sensitive   = true
}

variable "db_admin_password" {
  description = "PostgreSQL admin password"
  type        = string
  sensitive   = true
}

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default = {
    Project   = "cloud-native-platform"
    ManagedBy = "terraform"
  }
}
