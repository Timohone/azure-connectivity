# DNS Connection to Azure Contoso - DEPLOY AFTER BOTH ENVIRONMENTS EXIST
# =============================================================================

# DNS Forwarding Rules for Azure domains
resource "azurerm_private_dns_resolver_forwarding_rule" "azure_contoso" {
  name                      = "rule-azure-contoso"
  dns_forwarding_ruleset_id = azurerm_private_dns_resolver_dns_forwarding_ruleset.hub.id
  domain_name               = "azure.contoso.com."
  enabled                   = true

  target_dns_servers {
    ip_address = "10.0.35.4"
    port       = 53
  }

  depends_on = [
    azurerm_private_dns_resolver_dns_forwarding_ruleset.hub
  ]
}
