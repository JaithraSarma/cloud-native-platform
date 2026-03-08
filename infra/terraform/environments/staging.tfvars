# Staging Environment
environment        = "staging"
location           = "East US 2"
aks_node_count     = 2
aks_node_vm_size   = "Standard_D2s_v5"
aks_max_node_count = 4
postgres_sku       = "GP_Standard_D2ds_v4"
postgres_storage_mb = 65536

tags = {
  Project     = "cloud-native-platform"
  ManagedBy   = "terraform"
  Environment = "staging"
}
