#  Onprem Hub Gateway Configuration
# =============================================================================

# Public IP for VPN Gateway
resource "azurerm_public_ip" "vpn_gateway" {
  name                = "pip-onprem-hub-vpngw-001"
  location            = azurerm_resource_group.hub.location
  resource_group_name = azurerm_resource_group.hub.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]
}

# VPN Gateway
resource "azurerm_virtual_network_gateway" "vpn" {
  name                = "vpngw-onprem-hub-001"
  location            = azurerm_resource_group.hub.location
  resource_group_name = azurerm_resource_group.hub.name

  type     = "Vpn"
  vpn_type = "RouteBased"

  active_active = false
  enable_bgp    = true
  sku           = "VpnGw2AZ"
  generation    = "Generation2"

  bgp_settings {
    asn = 65002
    peering_addresses {
      ip_configuration_name = "vnetGatewayConfig"
    }
  }

  ip_configuration {
    name                          = "vnetGatewayConfig"
    public_ip_address_id          = azurerm_public_ip.vpn_gateway.id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.gateway.id
  }
}

# Local Network Gateway for Contoso
resource "azurerm_local_network_gateway" "to_contoso" {
  name                = "lngw-to-contoso"
  location            = azurerm_resource_group.hub.location
  resource_group_name = azurerm_resource_group.hub.name

  gateway_address = "108.141.96.93"
  address_space   = ["10.0.0.0/8"]
  bgp_settings {
    asn                 = 65001
    bgp_peering_address = "10.0.32.254"  
  }
}

# VPN Connection to Contoso
resource "azurerm_virtual_network_gateway_connection" "onprem_to_contoso" {
  name                = "onprem-to-contoso"
  location            = azurerm_resource_group.hub.location
  resource_group_name = azurerm_resource_group.hub.name

  type                       = "IPsec"
  virtual_network_gateway_id = azurerm_virtual_network_gateway.vpn.id
  local_network_gateway_id   = azurerm_local_network_gateway.to_contoso.id
  shared_key                 = "SharedKey123!"

  enable_bgp = true
}