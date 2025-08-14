# Contoso Hub DNS Configuration - NUR HUB DNS RESOLVER (VEREINFACHT)
# =============================================================================

# Data Source für OnPrem DNS Resolver
data "azurerm_private_dns_resolver_inbound_endpoint" "onprem" {
  name                    = "dnspr-onprem-hub-inbound"
  private_dns_resolver_id = data.azurerm_private_dns_resolver.onprem.id
}

data "azurerm_private_dns_resolver" "onprem" {
  name                = "dnspr-onprem-hub"
  resource_group_name = "rg-onprem-hub-p-weu"
  provider = azurerm.onprem
}

# =============================================================================
# DNS PRIVATE RESOLVER - NUR FÜR HUB
# =============================================================================

resource "azurerm_private_dns_resolver" "hub" {
  name                = "dnspr-nccont-hub"
  resource_group_name = azurerm_resource_group.hub.name
  location            = azurerm_resource_group.hub.location
  virtual_network_id  = azurerm_virtual_network.hub.id
}

resource "azurerm_private_dns_resolver_inbound_endpoint" "hub" {
  name                    = "dnspr-nccont-hub-inbound"
  private_dns_resolver_id = azurerm_private_dns_resolver.hub.id
  location                = azurerm_resource_group.hub.location

  ip_configurations {
    private_ip_allocation_method = "Dynamic"
    subnet_id = azurerm_subnet.dns_inbound.id
  }
}

resource "azurerm_private_dns_resolver_outbound_endpoint" "hub" {
  name                    = "dnspr-nccont-hub-outbound"
  private_dns_resolver_id = azurerm_private_dns_resolver.hub.id
  location                = azurerm_resource_group.hub.location
  subnet_id               = azurerm_subnet.dns_outbound.id
}

# =============================================================================
# DNS FORWARDING RULESET - NUR FÜR Onprem
# =============================================================================

resource "azurerm_private_dns_resolver_dns_forwarding_ruleset" "hub" {
  name                                       = "dnspr-nccont-hub-ruleset"
  resource_group_name                        = azurerm_resource_group.hub.name
  location                                   = azurerm_resource_group.hub.location
  private_dns_resolver_outbound_endpoint_ids = [azurerm_private_dns_resolver_outbound_endpoint.hub.id]
}

# Forwarding Rule für onprem.contoso.com (zu Onprem)
resource "azurerm_private_dns_resolver_forwarding_rule" "onprem_contoso" {
  name                      = "rule-onprem-contoso"
  dns_forwarding_ruleset_id = azurerm_private_dns_resolver_dns_forwarding_ruleset.hub.id
  domain_name               = "onprem.contoso.com."
  enabled                   = true

  target_dns_servers {
    ip_address = data.azurerm_private_dns_resolver_inbound_endpoint.onprem.ip_configurations[0].private_ip_address
    port       = 53
  }
}

# VNet Links für Hub UND alle Spokes (für Forwarding Rules)
resource "azurerm_private_dns_resolver_virtual_network_link" "hub" {
  name                      = "link-hub-ruleset"
  dns_forwarding_ruleset_id = azurerm_private_dns_resolver_dns_forwarding_ruleset.hub.id
  virtual_network_id        = azurerm_virtual_network.hub.id
}

# Links zu allen Spoke VNets für Forwarding Rules
resource "azurerm_private_dns_resolver_virtual_network_link" "app1_prod" {
  name                      = "link-app1-prod-ruleset"
  dns_forwarding_ruleset_id = azurerm_private_dns_resolver_dns_forwarding_ruleset.hub.id
  virtual_network_id        = azurerm_virtual_network.vnet_app1_prod.id
}

resource "azurerm_private_dns_resolver_virtual_network_link" "app1_nonprod" {
  name                      = "link-app1-nonprod-ruleset"
  dns_forwarding_ruleset_id = azurerm_private_dns_resolver_dns_forwarding_ruleset.hub.id
  virtual_network_id        = azurerm_virtual_network.vnet_app1_nonprod.id
}

resource "azurerm_private_dns_resolver_virtual_network_link" "hrportal_prod" {
  name                      = "link-hrportal-prod-ruleset"
  dns_forwarding_ruleset_id = azurerm_private_dns_resolver_dns_forwarding_ruleset.hub.id
  virtual_network_id        = azurerm_virtual_network.vnet_hrportal_prod.id
}

resource "azurerm_private_dns_resolver_virtual_network_link" "hrportal_nonprod" {
  name                      = "link-hrportal-nonprod-ruleset"
  dns_forwarding_ruleset_id = azurerm_private_dns_resolver_dns_forwarding_ruleset.hub.id
  virtual_network_id        = azurerm_virtual_network.vnet_hrportal_nonprod.id
}

resource "azurerm_private_dns_resolver_virtual_network_link" "ncae" {
  name                      = "link-ncae-ruleset"
  dns_forwarding_ruleset_id = azurerm_private_dns_resolver_dns_forwarding_ruleset.hub.id
  virtual_network_id        = azurerm_virtual_network.vnet_ncae.id
}

# =============================================================================
# HUB DNS ZONES - NUR AZURE.CONTOSO.COM (ONPREM IST IM ANDEREN REPO)
# =============================================================================

resource "azurerm_private_dns_zone" "azure_contoso" {
  name                = "azure.contoso.com"
  resource_group_name = azurerm_resource_group.hub.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "azure_contoso_hub" {
  name                  = "link-azure-contoso-hub"
  resource_group_name   = azurerm_resource_group.hub.name
  private_dns_zone_name = azurerm_private_dns_zone.azure_contoso.name
  virtual_network_id    = azurerm_virtual_network.hub.id
  registration_enabled  = true
}

# =============================================================================
# PRIVATE LINK ZONES - NUR IM HUB
# =============================================================================

locals {
  private_link_zones = [
    "privatelink.blob.core.windows.net",
    "privatelink.file.core.windows.net",
    "privatelink.database.windows.net",
    "privatelink.vaultcore.azure.net"
  ]
}

resource "azurerm_private_dns_zone" "private_endpoints" {
  for_each = toset(local.private_link_zones)

  name                = each.value
  resource_group_name = azurerm_resource_group.hub.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "private_endpoints_hub" {
  for_each = azurerm_private_dns_zone.private_endpoints

  name                  = "link-${replace(each.key, ".", "-")}-hub"
  resource_group_name   = azurerm_resource_group.hub.name
  private_dns_zone_name = each.value.name
  virtual_network_id    = azurerm_virtual_network.hub.id
  registration_enabled  = false
}

# =============================================================================
# HUB VNET DNS KONFIGURATION
# =============================================================================

resource "azurerm_virtual_network_dns_servers" "hub" {
  virtual_network_id = azurerm_virtual_network.hub.id
  dns_servers        = [azurerm_private_dns_resolver_inbound_endpoint.hub.ip_configurations[0].private_ip_address]
  
  depends_on = [azurerm_private_dns_resolver_inbound_endpoint.hub]
}

# =============================================================================
# OUTPUT FÜR SPOKE VNETs
# =============================================================================

output "hub_dns_resolver_ip" {
  description = "IP des Hub DNS Resolvers für Spokes"
  value       = azurerm_private_dns_resolver_inbound_endpoint.hub.ip_configurations[0].private_ip_address
}