output "eks_cluster_name" {
  value = aws_eks_cluster.main.name
}

output "eks_cluster_endpoint" {
  value = aws_eks_cluster.main.endpoint
}

output "eks_oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.eks.arn
}

output "ecr_api_repository_url" {
  value = aws_ecr_repository.api.repository_url
}

output "ecr_frontend_repository_url" {
  value = aws_ecr_repository.frontend.repository_url
}

output "rds_endpoint" {
  value = aws_db_instance.main.address
}

output "rds_database_name" {
  value = aws_db_instance.main.db_name
}

output "secrets_access_role_arn" {
  value = aws_iam_role.secrets_access.arn
}

output "secret_db_password_arn" {
  value = aws_secretsmanager_secret.db_password.arn
}

output "secret_db_connection_string_arn" {
  value = aws_secretsmanager_secret.db_connection_string.arn
}

output "secret_db_host_arn" {
  value = aws_secretsmanager_secret.db_host.arn
}

output "secret_db_user_arn" {
  value = aws_secretsmanager_secret.db_user.arn
}

output "account_id" {
  value = data.aws_caller_identity.current.account_id
}
