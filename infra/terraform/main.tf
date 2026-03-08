# ============================================================================
# Cloud-Native Platform - Azure Infrastructure
# All Azure-native services: AKS, ACR, PostgreSQL Flexible, Key Vault, Monitor
# ============================================================================

data "azurerm_client_config" "current" {}

locals {
  name_prefix = "${var.project_name}-${var.environment}"
  common_tags = merge(var.tags, {
    Environment = var.environment
  })
}

# -----------------------------------------------------------------------
# Resource Group
# -----------------------------------------------------------------------
resource "azurerm_resource_group" "main" {
  name     = "rg-${local.name_prefix}"
  location = var.location
  tags     = local.common_tags
}

# -----------------------------------------------------------------------
# Azure Container Registry (ACR)
# -----------------------------------------------------------------------
resource "azurerm_container_registry" "acr" {
  name                = replace("acr${local.name_prefix}", "-", "")
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = var.environment == "prod" ? "Premium" : "Basic"
  admin_enabled       = false
  tags                = local.common_tags
}

# -----------------------------------------------------------------------
# Log Analytics Workspace (for Azure Monitor / Container Insights)
# -----------------------------------------------------------------------
resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "PerGB2018"
  retention_in_days   = var.environment == "prod" ? 90 : 30
  tags                = local.common_tags
}

# -----------------------------------------------------------------------
# Azure Kubernetes Service (AKS) - with native addons
# -----------------------------------------------------------------------
resource "azurerm_kubernetes_cluster" "aks" {
  name                = "aks-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  dns_prefix          = "aks-${local.name_prefix}"
  kubernetes_version  = "1.29"
  tags                = local.common_tags

  default_node_pool {
    name                = "system"
    node_count          = var.aks_node_count
    vm_size             = var.aks_node_vm_size
    os_disk_size_gb     = 50
    auto_scaling_enabled = true
    min_count           = var.aks_node_count
    max_count           = var.aks_max_node_count
    max_pods            = 110
    zones               = var.environment == "prod" ? [1, 2, 3] : []

    upgrade_settings {
      max_surge = "33%"
    }
  }

  identity {
    type = "SystemAssigned"
  }

  # Azure Monitor / Container Insights (native observability)
  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  }

  # Azure native Web Application Routing (managed ingress)
  web_app_routing {
    dns_zone_ids = []
  }

  # Azure Key Vault Secrets Provider (native secrets management)
  key_vault_secrets_provider {
    secret_rotation_enabled  = true
    secret_rotation_interval = "2m"
  }

  network_profile {
    network_plugin    = "azure"
    network_policy    = "azure"
    load_balancer_sku = "standard"
    service_cidr      = "10.0.0.0/16"
    dns_service_ip    = "10.0.0.10"
  }

  azure_active_directory_role_based_access_control {
    azure_rbac_enabled = true
  }
}

# -----------------------------------------------------------------------
# Grant AKS → ACR pull access
# -----------------------------------------------------------------------
resource "azurerm_role_assignment" "aks_acr_pull" {
  principal_id                     = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
  role_definition_name             = "AcrPull"
  scope                            = azurerm_container_registry.acr.id
  skip_service_principal_aad_check = true
}

# -----------------------------------------------------------------------
# Azure Key Vault (native secrets management)
# -----------------------------------------------------------------------
resource "azurerm_key_vault" "main" {
  name                        = "kv-${local.name_prefix}"
  resource_group_name         = azurerm_resource_group.main.name
  location                    = azurerm_resource_group.main.location
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  sku_name                    = "standard"
  soft_delete_retention_days  = 7
  purge_protection_enabled    = var.environment == "prod"
  rbac_authorization_enabled  = true
  tags                        = local.common_tags
}

# Grant AKS managed identity access to Key Vault secrets
resource "azurerm_role_assignment" "aks_kv_secrets" {
  principal_id                     = azurerm_kubernetes_cluster.aks.key_vault_secrets_provider[0].secret_identity[0].object_id
  role_definition_name             = "Key Vault Secrets User"
  scope                            = azurerm_key_vault.main.id
  skip_service_principal_aad_check = true
}

# Store database password in Key Vault
resource "azurerm_role_assignment" "deployer_kv_admin" {
  principal_id         = data.azurerm_client_config.current.object_id
  role_definition_name = "Key Vault Administrator"
  scope                = azurerm_key_vault.main.id
}

resource "azurerm_key_vault_secret" "db_password" {
  name         = "db-password"
  value        = var.db_admin_password
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_role_assignment.deployer_kv_admin]
}

resource "azurerm_key_vault_secret" "db_connection_string" {
  name         = "db-connection-string"
  value        = "postgresql://${var.db_admin_username}:${var.db_admin_password}@${azurerm_postgresql_flexible_server.main.fqdn}:5432/${azurerm_postgresql_flexible_server_database.app.name}?sslmode=require"
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_role_assignment.deployer_kv_admin]
}

# -----------------------------------------------------------------------
# Azure Database for PostgreSQL Flexible Server (native managed database)
# -----------------------------------------------------------------------
resource "azurerm_postgresql_flexible_server" "main" {
  name                = "psql-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  version             = "16"

  administrator_login    = var.db_admin_username
  administrator_password = var.db_admin_password

  sku_name   = var.postgres_sku
  storage_mb = var.postgres_storage_mb
  zone       = var.environment == "prod" ? "1" : null

  backup_retention_days        = var.environment == "prod" ? 35 : 7
  geo_redundant_backup_enabled = var.environment == "prod"

  tags = local.common_tags
}

resource "azurerm_postgresql_flexible_server_database" "app" {
  name      = "cloudplatform"
  server_id = azurerm_postgresql_flexible_server.main.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

# Firewall rule: Allow Azure services
resource "azurerm_postgresql_flexible_server_firewall_rule" "allow_azure" {
  name             = "AllowAzureServices"
  server_id        = azurerm_postgresql_flexible_server.main.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# -----------------------------------------------------------------------
# Azure Monitor Alerts (native monitoring)
# -----------------------------------------------------------------------
resource "azurerm_monitor_action_group" "critical" {
  name                = "ag-${local.name_prefix}-critical"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "critical"
  tags                = local.common_tags
}

resource "azurerm_monitor_metric_alert" "node_cpu" {
  name                = "alert-${local.name_prefix}-high-cpu"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_kubernetes_cluster.aks.id]
  description         = "Alert when node CPU exceeds 80%"
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"
  tags                = local.common_tags

  criteria {
    metric_namespace = "Microsoft.ContainerService/managedClusters"
    metric_name      = "node_cpu_usage_percentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  action {
    action_group_id = azurerm_monitor_action_group.critical.id
  }
}

resource "azurerm_monitor_metric_alert" "node_memory" {
  name                = "alert-${local.name_prefix}-high-memory"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_kubernetes_cluster.aks.id]
  description         = "Alert when node memory exceeds 80%"
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"
  tags                = local.common_tags

  criteria {
    metric_namespace = "Microsoft.ContainerService/managedClusters"
    metric_name      = "node_memory_working_set_percentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  action {
    action_group_id = azurerm_monitor_action_group.critical.id
  }
}
