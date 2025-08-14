# Data Source für Hub DNS Resolver
data "azurerm_private_dns_resolver_inbound_endpoint" "hub" {
  name                    = "dnspr-nccont-hub-inbound"
  private_dns_resolver_id = data.azurerm_private_dns_resolver.hub.id
}

data "azurerm_private_dns_resolver" "hub" {
  name                = "dnspr-nccont-hub"
  resource_group_name = "rg-nccont-hub-p-weu"
}