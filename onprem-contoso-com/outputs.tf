# Outputs
output "onprem_hub_vnet" {
  description = "onprem hub virtual network"
  value = {
    id            = azurerm_virtual_network.hub.id
    name          = azurerm_virtual_network.hub.name
    address_space = azurerm_virtual_network.hub.address_space
  }
}

output "onprem_gateway_public_ip" {
  description = "onprem VPN Gateway public IP"
  value       = azurerm_public_ip.vpn_gateway.ip_address
}

output "onprem_dns_resolver_ip" {
  description = "onprem DNS resolver inbound IP"
  value       = azurerm_private_dns_resolver_inbound_endpoint.hub.ip_configurations[0].private_ip_address
}

output "onprem_hub_vm" {
  description = "onprem hub VM details"
  value = {
    name       = azurerm_linux_virtual_machine.hub_vm.name
    private_ip = azurerm_network_interface.hub_vm.private_ip_address
  }
}