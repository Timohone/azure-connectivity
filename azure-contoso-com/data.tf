# Data sources for cross-references
# =============================================================================

# Data source for hub DNS resolver (for spokes to reference)
data "azurerm_private_dns_resolver_inbound_endpoint" "hub" {
  name                    = "dnspr-nccont-hub-inbound"
  private_dns_resolver_id = azurerm_private_dns_resolver.hub.id
  
  depends_on = [azurerm_private_dns_resolver_inbound_endpoint.hub]
}

# Management group data sources for AVNM
data "azurerm_management_group" "hybrid_management_group" {
  name = "mgm-nccont-landingzones-hybrid"
}

data "azurerm_management_group" "root_management_group" {
  name = "mgm-nccont-root"
}

data "azurerm_management_group" "connectivity_management_group" {
  name = "mgm-nccont-foundation-connectivity"
}
