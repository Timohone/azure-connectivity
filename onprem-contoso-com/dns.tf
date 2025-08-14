# Onprem Hub DNS Configuration - UPDATED FÜR ONPREM.CONTOSO.COM
# =============================================================================

# Data Source für Contoso DNS Resolver
data "azurerm_private_dns_resolver" "contoso" {
  name                = "dnspr-nccont-hub"
  resource_group_name = "rg-nccont-hub-p-weu"

  provider = azurerm.contoso
}

data "azurerm_private_dns_resolver_inbound_endpoint" "contoso" {
  name                    = "dnspr-nccont-hub-inbound"
  private_dns_resolver_id = data.azurerm_private_dns_resolver.contoso.id
}

resource "azurerm_private_dns_resolver" "hub" {
  name                = "dnspr-onprem-hub"
  resource_group_name = azurerm_resource_group.hub.name
  location            = azurerm_resource_group.hub.location
  virtual_network_id  = azurerm_virtual_network.hub.id
}

resource "azurerm_private_dns_resolver_inbound_endpoint" "hub" {
  name                    = "dnspr-onprem-hub-inbound"
  private_dns_resolver_id = azurerm_private_dns_resolver.hub.id
  location                = azurerm_resource_group.hub.location

  ip_configurations {
    private_ip_allocation_method = "Dynamic"
    subnet_id = azurerm_subnet.dns_inbound.id
  }
}

resource "azurerm_private_dns_resolver_outbound_endpoint" "hub" {
  name                    = "dnspr-onprem-hub-outbound"
  private_dns_resolver_id = azurerm_private_dns_resolver.hub.id
  location                = azurerm_resource_group.hub.location
  subnet_id               = azurerm_subnet.dns_outbound.id
}

resource "azurerm_private_dns_resolver_dns_forwarding_ruleset" "hub" {
  name                                       = "dnspr-onprem-hub-ruleset"
  resource_group_name                        = azurerm_resource_group.hub.name
  location                                   = azurerm_resource_group.hub.location
  private_dns_resolver_outbound_endpoint_ids = [azurerm_private_dns_resolver_outbound_endpoint.hub.id]
}

# DNS Forwarding Rules - UPDATED FÜR NEUE DOMAINS
resource "azurerm_private_dns_resolver_forwarding_rule" "azure_contoso" {
  name                      = "rule-azure-contoso"
  dns_forwarding_ruleset_id = azurerm_private_dns_resolver_dns_forwarding_ruleset.hub.id
  domain_name               = "azure.contoso.com."
  enabled                   = true

  target_dns_servers {
    ip_address = data.azurerm_private_dns_resolver_inbound_endpoint.contoso.ip_configurations[0].private_ip_address
    port       = 53
  }
}

resource "azurerm_private_dns_resolver_virtual_network_link" "hub" {
  name                      = "link-onprem-hub-ruleset"
  dns_forwarding_ruleset_id = azurerm_private_dns_resolver_dns_forwarding_ruleset.hub.id
  virtual_network_id        = azurerm_virtual_network.hub.id
}

# Set DNS servers for Hub VNet
resource "azurerm_virtual_network_dns_servers" "hub" {
  virtual_network_id = azurerm_virtual_network.hub.id
  dns_servers        = [azurerm_private_dns_resolver_inbound_endpoint.hub.ip_configurations[0].private_ip_address]
}

# Private DNS Zones - KORRIGIERTER NAME FÜR ONPREM
resource "azurerm_private_dns_zone" "onprem_contoso" {
  name                = "onprem.contoso.com"
  resource_group_name = azurerm_resource_group.hub.name
}

# Private DNS Zone Links
resource "azurerm_private_dns_zone_virtual_network_link" "onprem_contoso_hub" {
  name                  = "link-onprem-contoso-hub"
  resource_group_name   = azurerm_resource_group.hub.name
  private_dns_zone_name = azurerm_private_dns_zone.onprem_contoso.name
  virtual_network_id    = azurerm_virtual_network.hub.id
  registration_enabled  = true
}