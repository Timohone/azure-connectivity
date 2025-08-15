# DNS Connection to OnPrem - DEPLOY AFTER BOTH ENVIRONMENTS EXIST
# =============================================================================

# Data Source for OnPrem DNS Resolver
data "azurerm_private_dns_resolver_inbound_endpoint" "onprem" {
  name                    = "dnspr-onprem-hub-inbound"
  private_dns_resolver_id = data.azurerm_private_dns_resolver.onprem.id
  
  provider = azurerm.onprem
}

data "azurerm_private_dns_resolver" "onprem" {
  name                = "dnspr-onprem-hub"
  resource_group_name = "rg-onprem-hub-p-weu"
  
  provider = azurerm.onprem
}

# Forwarding Rule for onprem.contoso.com (to OnPrem)
resource "azurerm_private_dns_resolver_forwarding_rule" "onprem_contoso" {
  name                      = "rule-onprem-contoso"
  dns_forwarding_ruleset_id = azurerm_private_dns_resolver_dns_forwarding_ruleset.hub.id
  domain_name               = "onprem.contoso.com."
  enabled                   = true

  target_dns_servers {
    ip_address = "10.64.4.4"
    port       = 53
  }

  depends_on = [
    azurerm_private_dns_resolver_dns_forwarding_ruleset.hub
  ]
}
