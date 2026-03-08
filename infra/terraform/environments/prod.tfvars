# Production Environment
environment        = "prod"
location           = "East US 2"
aks_node_count     = 3
aks_node_vm_size   = "Standard_D4s_v5"
aks_max_node_count = 10
postgres_sku       = "GP_Standard_D4ds_v4"
postgres_storage_mb = 131072

tags = {
  Project     = "cloud-native-platform"
  ManagedBy   = "terraform"
  Environment = "prod"
}
