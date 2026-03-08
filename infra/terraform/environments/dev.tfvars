# Development Environment
environment      = "dev"
location         = "East US 2"
aks_node_count   = 2
aks_node_vm_size = "Standard_D2s_v5"
aks_max_node_count = 3
postgres_sku     = "B_Standard_B1ms"
postgres_storage_mb = 32768

tags = {
  Project     = "cloud-native-platform"
  ManagedBy   = "terraform"
  Environment = "dev"
}
