# Onprem Hub Route Table Configuration
# =============================================================================

resource "azurerm_route_table" "management" {
  name                = "rt-onprem-hub-management"
  location            = azurerm_resource_group.hub.location
  resource_group_name = azurerm_resource_group.hub.name

  route {
    name                   = "ContosoNetworks"
    address_prefix         = "10.0.0.0/8"
    next_hop_type          = "VirtualNetworkGateway"
  }

  tags = {
    usecase      = "hub"
    organization = "onprem"
  }
}

# Associate Route Table with Management Subnet
resource "azurerm_subnet_route_table_association" "management" {
  subnet_id      = azurerm_subnet.management.id
  route_table_id = azurerm_route_table.management.id
}